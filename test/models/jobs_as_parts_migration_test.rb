require "test_helper"
require Rails.root.join("db/migrate/20261123000000_jobs_as_parts_of_a_quote.rb").to_s

# JOB-09's migration on existing data: each job claims its quote's lines, matched by position on
# catalog item, name and unit price, clamped to the quantities; unmatched lines are claimed with
# no job line; cancelled jobs' claims aren't live; no total changes. Down refuses two jobs.
class JobsAsPartsMigrationTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
  end

  def approved_quote(rows)
    as_business(@business) do
      client = Client.create!(display_name: "Old Client #{rows.size}", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:)
      quote.sync_line_items(rows.each_with_index.map { |(name, quantity, price), index| { "key" => "k#{index}", "name" => name, "quantity" => quantity.to_s, "unit_price" => price.to_s } })
      quote.save!
      quote.update_columns(status: "approved")
      quote.reload
    end
  end

  # As before JOB-09: jobs without claims.
  def forget_claims
    as_business(@business) do
      JobClaim.delete_all
      QuoteLineItem.update_all(claimed_quantity: 0)
    end
  end

  # A second invoice of the same quote's lines, as the app made them before JOB-09 (it refuses them now).
  def legacy_copy(quote)
    as_business(@business) do
      invoice = Invoice.new(client: quote.client, property: quote.property, quote:, title: quote.title, currency: quote.currency)
      invoice.copy_pricing_from(quote, lines: [])
      invoice.sync_line_items(BuiltDocument.rows_from(quote.line_items.to_a))
      invoice.save!
      invoice
    end
  end

  def migrate = ActiveRecord::Migration.suppress_messages { JobsAsPartsOfAQuote.new.tap { _1.claim_existing_jobs && _1.claim_direct_billing } }

  test "existing jobs claim their quote's lines, matched and clamped, with no total changed" do
    quote = approved_quote([ [ "Mowing", 1, 40 ], [ "Trees", 10, 100 ], [ "Trees", 2, 100 ], [ "Mulch", 6, 78 ], [ "Edging", 3, 20 ] ])
    job = as_business(@business) { Job.from_quote!(quote) }
    mowing, trees, more_trees, mulch, edging = as_business(@business) { job.line_items.to_a }
    as_business(@business) do
      trees.update_columns(quantity: 7) # lowered on the job
      mulch.update_columns(quantity: 9) # raised past the quote
      edging.update_columns(name: "Edging (front)") # renamed: no match
      mowing.delete # removed from the job
      job.reload.save!
    end
    totals = as_business(@business) { [ job.reload.total_cents, quote.reload.total_cents ] }
    forget_claims
    migrate

    as_business(@business) do
      claims = job.claims.includes(:quote_line_item).sort_by { _1.quote_line_item.position }
      assert_equal [ [ "Mowing", nil, 1 ], [ "Trees", trees.id, 7 ], [ "Trees", more_trees.id, 2 ], [ "Mulch", mulch.id, 6 ], [ "Edging", nil, 3 ] ],
                   claims.map { [ _1.quote_line_item.name, _1.job_line_item_id, _1.quantity.to_i ] }
      assert_equal [ 1, 7, 2, 6, 3 ], quote.line_items.map { _1.reload.claimed_quantity.to_i }
      assert_equal totals, [ job.reload.total_cents, quote.reload.total_cents ], "no total changes"
      assert_empty JobClaim.unreconciled_lines
    end
  end

  test "a cancelled job keeps claims that aren't live, so reopening takes them back" do
    quote = approved_quote([ [ "Trees", 10, 100 ] ])
    job = as_business(@business) { Job.from_quote!(quote) }
    as_business(@business) { job.update_columns(status: "cancelled", cancelled_at: Time.current) }
    forget_claims
    migrate
    as_business(@business) do
      assert_equal [ 10 ], job.claims.map { _1.quantity.to_i }
      assert_equal 0, quote.line_items.first.reload.claimed_quantity
      assert_empty JobClaim.unreconciled_lines
      job.reload.reopen!
      assert_equal 10, quote.line_items.first.reload.claimed_quantity
    end
  end

  test "approved quotes without a job have everything to do" do
    quote = approved_quote([ [ "Trees", 10, 100 ] ])
    forget_claims
    migrate
    assert_equal 10, as_business(@business) { quote.line_items.first.reload.to_do_quantity }
  end

  test "a quote billed directly, with no job, claims what its invoices bill, so it isn't to do again" do
    quote = approved_quote([ [ "Trees", 10, 100 ], [ "Gutters", 1, 200 ] ])
    first = as_business(@business) { Invoice.from_quote!(quote) }
    second = legacy_copy(quote) # made before JOB-09, when a repeat was progress: nothing left to claim
    voided = legacy_copy(quote).tap { |invoice| as_business(@business) { invoice.update_columns(status: "void") } }
    forget_claims
    migrate
    as_business(@business) do
      claims = JobClaim.where(quote_line_item_id: quote.line_items.ids).includes(:invoice_line_item).order(:quote_line_item_id)
      assert_equal [ [ nil, first.id, 10 ], [ nil, first.id, 1 ] ], claims.map { [ _1.job_id, _1.invoice_line_item.invoice_id, _1.quantity.to_i ] }
      assert_equal [ 0, 0 ], quote.line_items.map { _1.reload.to_do_quantity.to_i }
      assert_empty JobClaim.unreconciled_lines
      assert second && voided
    end
  end

  test "down refuses once a quote has two jobs" do
    quote = approved_quote([ [ "Trees", 10, 100 ] ])
    as_business(@business) { 2.times { Job.create!(client: quote.client, quote:, title: "Trees") } }
    assert_raises(ActiveRecord::IrreversibleMigration) { ActiveRecord::Migration.suppress_messages { JobsAsPartsOfAQuote.new.migrate(:down) } }
  end
end
