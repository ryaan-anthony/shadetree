require "test_helper"
require Rails.root.join("db/migrate/20261124000000_billing_completed_work.rb").to_s

# PAY-06's migration on existing data, kept simple (owner, 2026-11-23): invoice lines that aren't
# void are linked to the job or quote lines they came from (same item, name and price), the
# earliest sent invoice of a line being its final bill and later ones progress; a quote's invoice
# on a quote with a job links to the job's lines. Lines carry their invoice's status.
class BillingCompletedWorkMigrationTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
  end

  def approved_quote(name, rows)
    as_business(@business) do
      client = Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:)
      quote.sync_line_items(rows.each_with_index.map { |(item, quantity, price), index| { "key" => "k#{index}", "name" => item, "quantity" => quantity.to_s, "unit_price" => price.to_s } })
      quote.save!
      quote.update_columns(status: "approved")
      quote.reload
    end
  end

  def job_for(quote, status: "completed")
    as_business(@business) { Job.from_quote!(quote).tap { _1.update_columns(status:) } }
  end

  def sent(invoice, status: "sent")
    as_business(@business) { invoice.update_columns(status:, sent_at: Time.current) }
    invoice
  end

  # An invoice as made before PAY-06: a copy of a job's lines (or a quote's) with no links, which
  # the app no longer makes (a second bill of the same work is refused), so built by hand.
  def legacy_invoice(source)
    as_business(@business) do
      job = source if source.is_a?(Job)
      invoice = Invoice.new(client: source.client, property: source.property, job:, quote: job ? job.quote : source, title: source.title, currency: source.currency)
      invoice.copy_pricing_from(source, lines: [])
      invoice.sync_line_items(BuiltDocument.rows_from(source.line_items.to_a))
      invoice.save!
      invoice
    end
  end
  def from_job(job) = legacy_invoice(job)
  def from_quote(quote) = legacy_invoice(quote)

  # As before PAY-06: no links, no join rows.
  def forget_links
    as_business(@business) do
      InvoiceLineItem.update_all(job_line_item_id: nil, quote_line_item_id: nil, final: false)
      InvoiceJob.delete_all
    end
  end

  def migrate = ActiveRecord::Migration.suppress_messages { BillingCompletedWork.new.link_existing_invoices }

  # The rule before PAY-06: completed, with no invoice that went out for the job or its quote.
  def legacy_ready_to_invoice
    as_business(@business) do
      sent = Invoice.where.not(status: "void").where.not(sent_at: nil)
      Job.where(status: "completed").where.not(id: sent.where.not(job_id: nil).select(:job_id))
         .where("jobs.quote_id IS NULL OR jobs.quote_id NOT IN (?)", sent.where.not(quote_id: nil).select(:quote_id)).ids.sort
    end
  end

  def links(invoice) = as_business(@business) { invoice.line_items.reload.map { [ _1.job_line_item_id, _1.quote_line_item_id, _1.final ] } }

  test "job invoices link to the job's lines and their quote lines; a second bill of a line is progress; void and repriced lines stay unlinked" do
    quote = approved_quote("Pat", [ [ "Trees", 10, 100 ], [ "Gutters", 1, 200 ] ])
    job = job_for(quote)
    first, second, voided = 3.times.map { from_job(job) }
    sent(voided, status: "void")
    as_business(@business) { first.line_items.last.update!(unit_price: "250") } # repriced on the invoice: not matched
    forget_links
    migrate

    trees, gutters = as_business(@business) { job.line_items.to_a }
    quote_trees, quote_gutters = as_business(@business) { quote.line_items.to_a }
    assert_equal [ [ trees.id, quote_trees.id, true ], [ nil, nil, false ] ], links(first)
    assert_equal [ [ trees.id, quote_trees.id, false ], [ gutters.id, quote_gutters.id, true ] ], links(second)
    assert_equal [ [ nil, nil, false ], [ nil, nil, false ] ], links(voided)
    assert_equal [ first, second, voided ].map(&:id), as_business(@business) { job.invoices.order(:id).ids }
  end

  test "a quote's invoice on a quote with a job links to the job's lines, and the earliest invoice is the final bill" do
    quote = approved_quote("Lee", [ [ "Trees", 10, 100 ] ])
    from_quote = from_quote(quote)
    job = job_for(quote)
    from_job = from_job(job)
    forget_links
    as_business(@business) { from_quote.update_columns(job_id: nil) } # billed before the job was made
    migrate

    job_line, quote_line = as_business(@business) { [ job.line_items.sole.id, quote.line_items.sole.id ] }
    assert_equal [ [ job_line, quote_line, true ] ], links(from_quote)
    assert_equal [ [ job_line, quote_line, false ] ], links(from_job)
    assert_equal job.id, from_quote.reload.job_id
    assert_includes as_business(@business) { job.invoices.ids }, from_quote.id
  end

  test "a quote billed directly links to its quote lines; a sent invoice is the final bill before an older draft" do
    quote = approved_quote("Kim", [ [ "Trees", 10, 100 ], [ "Gutters", 1, 200 ] ])
    draft, sent_one = 2.times.map { from_quote(quote) }
    sent(sent_one)
    forget_links
    migrate

    ids = as_business(@business) { quote.line_items.ids }
    assert_equal ids.map { [ nil, _1, true ] }, links(sent_one)
    assert_equal ids.map { [ nil, _1, false ] }, links(draft)
  end

  test "lines carry their invoice's status, and the database refuses a draft line on a sent invoice" do
    quote = approved_quote("Ash", [ [ "Trees", 10, 100 ] ])
    invoice = sent(from_quote(quote), status: "paid")
    assert_equal [ "paid" ], as_business(@business) { invoice.line_items.reload.map(&:invoice_status) }
    assert_raises(ActiveRecord::InvalidForeignKey) do
      as_business(@business) { InvoiceLineItem.create!(invoice:, key: "late", name: "Late", quantity: 1, unit_price: "5") }
    end
  end

  test "the backstop: a second final bill for a line is refused until the first one's invoice is void" do
    job = job_for(approved_quote("Sam", [ [ "Trees", 10, 100 ] ]))
    first, second = 2.times.map { from_job(job) }
    forget_links
    job_line = as_business(@business) { job.line_items.sole }
    final = ->(invoice) { as_business(@business) { invoice.line_items.sole.update_columns(job_line_item_id: job_line.id, final: true) } }
    final.(first)
    assert_raises(ActiveRecord::RecordNotUnique) { ActiveRecord::Base.transaction(requires_new: true) { final.(second) } }
    sent(first, status: "void") # the lines follow their invoice: voided, it frees the line
    assert_nothing_raised { final.(second) }
    assert_equal [ "void" ], as_business(@business) { first.line_items.reload.map(&:invoice_status) }
  end

  test "Ready to invoice lists the same jobs before and after for matched data" do
    never = job_for(approved_quote("Never billed", [ [ "Trees", 3, 100 ] ]))
    billed = job_for(approved_quote("Billed", [ [ "Trees", 3, 100 ], [ "Mulch", 2, 30 ] ])).tap { sent(from_job(_1)) }
    twice = job_for(approved_quote("Twice", [ [ "Trees", 3, 100 ] ])).tap { |job| 2.times { sent(from_job(job)) } }
    by_quote = job_for(quote = approved_quote("By quote", [ [ "Trees", 3, 100 ] ]))
    sent(from_quote(quote)).update_columns(job_id: nil)
    draft_only = job_for(approved_quote("Draft only", [ [ "Trees", 3, 100 ] ])).tap { from_job(_1) }
    voided = job_for(approved_quote("Voided", [ [ "Trees", 3, 100 ] ])).tap { sent(from_job(_1), status: "void") }
    open_job = job_for(approved_quote("Open", [ [ "Trees", 3, 100 ] ]), status: "in_progress").tap { sent(from_job(_1)) }
    loose, loose_billed = 2.times.map do |index|
      as_business(@business) do
        client = Client.create!(display_name: "Walk-in #{index}", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
        Job.create!(client:, title: "Fence", line_items_attributes: [ { name: "Fence", quantity: 1, unit_price: "400" } ]).tap { _1.update_columns(status: "completed") }
      end
    end
    sent(from_job(loose_billed))
    forget_links
    before = legacy_ready_to_invoice
    migrate

    assert_equal [ never, draft_only, voided, loose ].map(&:id).sort, before
    assert_equal before, as_business(@business) { Job.ready_to_invoice.ids.sort }
    assert [ billed, twice, by_quote, open_job ].all?
  end
end
