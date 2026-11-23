require "test_helper"

# JOB-09: a quote's work shared among jobs through claims: splits, refusals, the picker's token,
# raising and lowering on the job form, cancel and reopen, and the database's check. Every test ends reconciled: each line's claimed quantity is the sum of its live claims.
class QuoteWorkTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.title = "Yard work"
      quote.set_discount("amount", "50")
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100" },
                              { "key" => "g", "name" => "Gutters", "quantity" => "1", "unit_price" => "200", "discount_kind" => "percent", "discount_value" => "10" },
                              { "key" => "h", "name" => "Haul away", "quantity" => "2", "unit_price" => "40", "discount_kind" => "amount", "discount_value" => "5" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      @business.update!(auto_create_jobs: false)
      quote.record_response!(:approve, by: @owner, signer_name: "Pat Lee", message: "By phone")
      quote.reload
    end
  end

  teardown { assert_empty as_business(@business) { JobClaim.unreconciled_lines.pluck(:id) }, "claimed = the sum of live claims" }

  def line(key) = as_business(@business) { @quote.line_items.find_by!(key:).reload }
  def pick(**quantities) = quantities.to_h { [ line(_1.to_s).id, _2.to_s ] }
  def split! = enable_feature(:split_jobs)
  def make(**quantities) = as_business(@business) { Job.from_quote!(@quote, by: @owner, picks: pick(**quantities)) }

  test "flag off: one job takes everything with its discounts, and a second press opens it" do
    job = as_business(@business) { Job.from_quote!(@quote, by: @owner) }
    as_business(@business) do
      assert_equal [ "Yard work", "amount", 5_000 ], [ job.title, job.discount_kind, job.discount_amount_cents ]
      assert_equal [ [ "Tree removal", 10 ], [ "Gutters", 1 ], [ "Haul away", 2 ] ], job.line_items.map { [ _1.name, _1.quantity.to_i ] }
      assert_equal [ 10, 1, 2 ], @quote.line_items.map { _1.reload.claimed_quantity.to_i }
      assert_equal job.line_items.map(&:id), job.claims.order(:quote_line_item_id).map(&:job_line_item_id)
      assert_equal job, Job.from_quote!(@quote)
    end
  end

  test "flag off: a job line raised past the quote claims only what's free, as before" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) do
      trees = job.line_items.first
      job.update!(line_items_attributes: job.line_items.map { { id: _1.id } }.tap { _1[0][:quantity] = "12" })
      assert_equal [ 12, 10 ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
    end
  end

  test "cancelling frees the work and reopening takes it back" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) { job.cancel!(by: @owner, notify_client: false) }
    assert_equal [ 0, 0, 0 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    assert_equal [ 10, 1, 2 ], as_business(@business) { job.claims.order(:quote_line_item_id).map { _1.quantity.to_i } }, "kept for a reopen"
    as_business(@business) { job.reload.reopen! }
    assert_equal [ 10, 1, 2 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
  end

  test "removing a quote line from a job frees it" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) do
      rows = job.line_items.map { { id: _1.id } }
      rows[0][:quantity] = "4"
      rows[1][:_destroy] = "1"
      job.update!(line_items_attributes: rows)
      assert_equal [ 4, 0, 2 ], @quote.line_items.map { _1.reload.claimed_quantity.to_i }
    end
  end

  test "the database refuses claims past a line's quantity, or below zero" do
    trees = line("t")
    as_business(@business) do
      [ 11, -1 ].each do |claimed|
        assert_raises(ActiveRecord::CheckViolation) { QuoteLineItem.transaction(requires_new: true) { QuoteLineItem.where(id: trees.id).update_all(claimed_quantity: claimed) } }
      end
    end
  end

  test "work entries are only ever added" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    entry = as_business(@business) { WorkEntry.create!(job:, job_line_item: job.line_items.first, user: @owner, quantity: 2) }
    as_business(@business) do
      assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(quantity: 3) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
    end
  end

  test "an invoice straight from a quote with no job claims its lines; voiding or deleting it frees them" do
    sent = as_business(@business) { Invoice.from_quote!(@quote) }
    draft = as_business(@business) { Invoice.from_quote!(@quote) }
    assert_equal [ 10, 1, 2 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    assert_equal 0, as_business(@business) { JobClaim.joins(:invoice_line_item).where(invoice_line_items: { invoice_id: draft.id }).count }, "nothing left for a second one"
    job = as_business(@business) { Job.from_quote!(@quote) }
    assert_equal [ [ 10, 0 ], [ 1, 0 ], [ 2, 0 ] ], as_business(@business) { job.line_items.map { [ _1.quantity.to_i, _1.claim.quantity.to_i ] } }, "flag off: a job copies the quote in full, claiming only what's free"
    as_business(@business) do
      job.cancel!(by: @owner, notify_client: false)
      sent.update_columns(sent_at: Time.current)
      sent.void!(reason: "Wrong client", by: @owner)
    end
    assert_equal [ 0, 0, 0 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    another = as_business(@business) { Invoice.from_quote!(@quote) }
    assert_equal 10, line("t").claimed_quantity
    as_business(@business) { another.destroy! }
    assert_equal 0, line("t").claimed_quantity
  end

  test "removing a job line keeps its work log" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    trees = as_business(@business) { job.line_items.first }
    as_business(@business) do
      WorkEntry.create!(job:, job_line_item: trees, user: @owner, quantity: 3)
      job.update!(line_items_attributes: job.line_items.map { { id: _1.id } }.tap { _1[0][:_destroy] = "1" })
      entry = WorkEntry.sole
      assert_equal [ nil, "Tree removal", 3, @owner.id ], [ entry.job_line_item_id, entry.item_name, entry.quantity.to_i, entry.user_id ]
    end
  end
end
