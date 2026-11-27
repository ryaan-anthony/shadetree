require "test_helper"

# PAY-06: invoices bill completed work, once. A job's invoice bills its lines as done; the quote's
# bills every completed job's unbilled lines and can be used again; a quote with no jobs is billed
# directly; voiding or deleting frees what was billed; mixed tax rates stay per line. Every test
# ends reconciled (JOB-09): each quote line's claimed quantity is the sum of its live claims.
class WorkBillingTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.title = "Yard work"
      quote.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "10") ]
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100", "taxable" => "1" },
                              { "key" => "g", "name" => "Gutters", "quantity" => "1", "unit_price" => "200", "taxable" => "1" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      @business.update!(auto_create_jobs: false)
      quote.record_response!(:approve, by: @owner, signer_name: "Pat Lee", message: "By phone")
      quote.reload
    end
  end

  teardown { assert_empty as_business(@business) { JobClaim.unreconciled_lines.pluck(:id) }, "claimed = the sum of live claims" }

  def line(key) = as_business(@business) { @quote.line_items.find_by!(key:).reload }
  def make(**quantities) = as_business(@business) { Job.from_quote!(@quote, by: @owner, picks: quantities.to_h { [ line(_1.to_s).id, _2.to_s ] }) }
  def complete(job, done = {})
    as_business(@business) { job.reload.complete!(by: @owner, done: done.to_h { |name, quantity| [ job.line_items.find_by!(name:).id, quantity.to_s ] }) }
    job
  end
  def bill_job(job) = as_business(@business) { Invoice.from_job!(job.reload, by: @owner) }
  def bill_quote = as_business(@business) { Invoice.from_quote!(@quote.reload, by: @owner) }
  def billed(invoice) = as_business(@business) { invoice.line_items.reload.map { [ _1.name, _1.quantity.to_i, _1.final ] } }

  test "a completed job's invoice bills its lines as done; an open job and a billed one are refused" do
    job = make(t: 6)
    error = assert_raises(WorkBilling::Refused) { bill_job(job) }
    assert_equal "#{job.number} isn't completed yet. An invoice bills completed work.", error.message

    complete(job, "Tree removal" => 5)
    invoice = bill_job(job)
    as_business(@business) do
      assert_equal [ [ "Tree removal", 5, true ] ], billed(invoice)
      assert_equal [ job.line_items.sole.id, line("t").id ], invoice.line_items.sole.then { [ _1.job_line_item_id, _1.quote_line_item_id ] }
      assert_equal [ job ], invoice.jobs.to_a
    end
    error = assert_raises(WorkBilling::Refused) { bill_job(job) }
    assert_equal "Everything on #{job.number} is billed (#{invoice.number}).", error.message
  end

  test "the quote's invoice bills every completed job's unbilled lines, again as more finish, alongside a job's own invoice" do
    trees, more_trees, gutters = make(t: 6), make(t: 4), make(g: 1)
    error = assert_raises(WorkBilling::Refused) { bill_quote }
    assert_equal "Nothing on #{@quote.number} is ready to bill: #{trees.number}, #{more_trees.number}, and #{gutters.number} aren't completed yet.", error.message

    [ trees, gutters ].each { complete(_1) }
    own = bill_job(gutters)
    first = bill_quote
    assert_equal [ [ "Tree removal", 6, true ] ], billed(first), "the gutters were billed on their own invoice"
    assert_equal [ trees.id ], as_business(@business) { first.jobs.ids }

    complete(more_trees)
    second = bill_quote
    assert_equal [ [ "Tree removal", 4, true ] ], billed(second)
    assert_equal more_trees.id, second.job_id
    assert_match "Everything done on #{@quote.number} is billed.", assert_raises(WorkBilling::Refused) { bill_quote }.message
    assert own
  end

  test "a quote invoice over jobs with different tax rates keeps each job's rates on its lines" do
    trees, gutters = make(t: 10), make(g: 1)
    as_business(@business) { gutters.update_columns(tax_rates: [ { "name" => "County", "percent" => "5" } ]) }
    [ trees, gutters ].each { complete(_1) }
    invoice = bill_quote
    as_business(@business) do
      assert_equal [ nil, [ { "name" => "County", "percent" => "5" } ] ], invoice.line_items.map(&:tax_rates)
      assert_equal [ [ "State", 10_000 ], [ "County", 1_000 ] ], invoice.totals.taxes.map { [ _1.rate.name, _1.amount.cents ] }
      assert_equal 120_000 + 10_000 + 1_000, invoice.total_cents
    end
  end

  test "a quote with no jobs is billed directly, so no job can take its work; voiding frees it, and it can be billed again" do
    invoice = bill_quote
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(invoice)
    assert_equal [ 0, 0 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert_raises(Job::NotOpen) { as_business(@business) { Job.from_quote!(@quote.reload) } }
    assert_match "Everything on #{@quote.number} is billed.", assert_raises(WorkBilling::Refused) { bill_quote }.message

    as_business(@business) { invoice.update_columns(sent_at: Time.current, status: "sent") && invoice.reload.void!(reason: "Wrong client", by: @owner) }
    assert_equal [ 10, 1 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(bill_quote)
  end

  test "every job cancelled bills the quote directly; a recurring quote isn't billed directly" do
    job = make(t: 4)
    as_business(@business) { job.cancel!(by: @owner, notify_client: false) }
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(bill_quote)

    as_business(@business) { Invoice.where(quote: @quote).find_each(&:destroy!) }
    @quote.define_singleton_method(:recurring?) { true }
    error = assert_raises(WorkBilling::Refused) { as_business(@business) { Invoice.from_quote!(@quote, by: @owner) } } # JOB-10 sets recurring?
    assert_match "is recurring", error.message
  end

  test "deleting a draft frees its lines; a directly billed line follows its quantity on the draft and frees what it drops" do
    invoice = bill_quote
    as_business(@business) do
      invoice.reload.sync_line_items(invoice.line_items.map { { "key" => _1.key, "name" => _1.name, "quantity" => _1.key == invoice.line_items.first.key ? "7" : _1.quantity.to_s, "unit_price" => _1.unit_price.to_s } })
      invoice.save!
    end
    assert_equal 3, line("t").to_do_quantity.to_i, "lowered on the draft: three trees are to do again"
    job = make(t: 3)
    as_business(@business) { invoice.reload.destroy! }
    assert_equal [ 7, 1 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert job
  end

  test "voiding a job's invoice frees its lines to be billed again; a discarded revision keeps what its lines bill" do
    job = complete(make(t: 10))
    invoice = bill_job(job)
    as_business(@business) do
      invoice.mark_sent!(by: @owner, channel: "link")
      invoice.reload.revise!(by: @owner)
      invoice.sync_line_items(invoice.line_items.map { { "key" => _1.key, "name" => _1.name, "quantity" => "4", "unit_price" => _1.unit_price.to_s } } +
                              [ { "key" => "typed", "name" => "Typed", "quantity" => "1", "unit_price" => "5" } ])
      invoice.save!
      invoice.reload.discard_revision!(by: @owner)
    end
    assert_equal [ [ "Tree removal", 10, true ] ], billed(invoice)
    assert_equal as_business(@business) { job.line_items.sole.id }, as_business(@business) { invoice.line_items.sole.job_line_item_id }
    assert_raises(WorkBilling::Refused) { bill_job(job) }

    as_business(@business) { invoice.reload.void!(reason: "Redo", by: @owner) }
    assert_equal [ [ "Tree removal", 10, true ] ], billed(bill_job(job))
  end

  def edit_lines(invoice, quantities = {}, drop: [])
    as_business(@business) do
      invoice.reload
      rows = invoice.line_items.reject { drop.include?(_1.name) }.map { { "key" => _1.key, "name" => _1.name, "quantity" => (quantities[_1.name] || _1.quantity).to_s, "unit_price" => _1.unit_price.to_s } }
      invoice.sync_line_items(rows)
      invoice.save
    end
  end

  test "B1: a direct line on a draft can't bill more than its claim covers: lowered, a job takes the rest, raising it back is refused" do
    invoice = bill_quote
    assert edit_lines(invoice, { "Tree removal" => 7 })
    job = make(t: 3)
    assert_not edit_lines(invoice, { "Tree removal" => 10 })
    assert_equal [ "Tree removal: only 7 are free to bill; the rest is on #{job.number}." ], invoice.errors[:base]
    as_business(@business) do
      assert_equal [ 7, 7 ], [ invoice.reload.line_items.first.quantity.to_i, invoice.line_items.first.direct_claim.quantity.to_i ]
    end
    assert edit_lines(invoice, { "Tree removal" => 6 }), "lowering still frees"
    assert_equal 1, line("t").to_do_quantity.to_i
  end

  test "R1: a sent invoice's revision frees nothing: lowering holds the work, taking off a billed line is refused, discarding restores it" do
    invoice = bill_quote
    as_business(@business) { invoice.reload.mark_sent!(by: @owner, channel: "link") && invoice.reload.revise!(by: @owner) }
    assert edit_lines(invoice, { "Tree removal" => 7 })
    assert_equal 0, line("t").to_do_quantity.to_i, "the 3 trees stay invoiced until it's voided"
    assert_raises(QuoteWork::Refused) { make(t: 3) }
    assert_not edit_lines(invoice, drop: [ "Gutters" ])
    assert_equal [ "Gutters is invoiced work. Void the invoice to take it off." ], invoice.errors[:base]

    as_business(@business) { invoice.reload.discard_revision!(by: @owner) }
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(invoice)
    assert_equal [ 10, 1 ], as_business(@business) { invoice.line_items.map { _1.direct_claim.quantity.to_i } }
  end

  test "a card payment during a revision that took a line off records, back on the version the client was sent" do
    invoice = bill_quote
    as_business(@business) do
      invoice.reload.sync_line_items(invoice.line_items.map { { "key" => _1.key, "name" => _1.name, "quantity" => _1.quantity.to_s, "unit_price" => _1.unit_price.to_s } } +
                                     [ { "key" => "typed", "name" => "Call-out", "quantity" => "1", "unit_price" => "40" } ])
      invoice.save!
      invoice.reload.mark_sent!(by: @owner, channel: "link")
      invoice.reload.revise!(by: @owner)
    end
    assert edit_lines(invoice, { "Tree removal" => 8 }, drop: [ "Call-out" ])
    payment, created, = as_business(@business) { invoice.reload.record_online_payment!(intent_id: "pi_rev", amount_cents: 5_000, currency: "usd") }
    assert created
    assert_equal [ "partially_paid", 1 ], [ invoice.reload.status, invoice.revision ]
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ], [ "Call-out", 1, false ] ], billed(invoice)
    assert_equal 5_000, payment.amount_cents
  end

  test "a job line billed on an invoice that isn't void can't be removed from the job" do
    job = complete(as_business(@business) { Job.from_quote!(@quote, by: @owner) })
    invoice = bill_job(job)
    as_business(@business) do
      gutters = job.reload.line_items.find_by!(name: "Gutters")
      assert_not job.update(line_items_attributes: [ { id: gutters.id, _destroy: "1" } ])
      assert_equal [ "Gutters is billed on #{invoice.number}. Void the invoice first to remove it." ], job.errors[:base]
    end
  end

  test "a quote invoice over jobs that differ on whether prices include tax is refused" do
    trees, gutters = make(t: 10), make(g: 1)
    as_business(@business) { gutters.update_columns(prices_include_tax: true) }
    [ trees, gutters ].each { complete(_1) }
    error = assert_raises(WorkBilling::Refused) { bill_quote }
    assert_equal "#{trees.number} and #{gutters.number} differ on whether prices include tax. Bill each from its own page.", error.message
    assert_equal [ trees.id, gutters.id ].to_set, as_business(@business) { WorkBilling.billable_job_ids([ trees.reload, gutters.reload ]) }
  end

  test "the database refuses a second final bill that got past the lock" do
    job = complete(make(t: 10))
    invoice = bill_job(job)
    copy = as_business(@business) { Invoice.start(client: @quote.client) }
    assert_raises(ActiveRecord::RecordNotUnique) do
      as_business(@business) { InvoiceLineItem.create!(invoice: copy, key: "x", name: "Again", quantity: 1, unit_price: "1", job_line_item_id: invoice.line_items.sole.job_line_item_id, final: true) }
    end
  end

  test "another business's job isn't found for billing" do
    job = complete(make(t: 10))
    assert_raises(ActiveRecord::RecordNotFound) { as_business(businesses(:two)) { Invoice.from_job!(Job.find_by_param!(job.uid)) } }
  end
end

# The automation and a click at the same moment: the lock queues the second, which finds nothing
# left to bill, and the database would refuse it anyway.
class WorkBillingRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two invoices for the same completed job at once: one gets it" do
    business = businesses(:one)
    job = as_business(business) do
      client = Client.create!(display_name: "Race", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "t", "name" => "Trees", "quantity" => "10", "unit_price" => "100" } ])
        _1.save!
        _1.update_columns(status: "approved")
      end
      Job.from_quote!(quote).tap { _1.complete!(by: nil) }
    end
    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          as_business(business) { Invoice.from_job!(Job.find(job.id)) && :billed }
        rescue WorkBilling::Refused
          :refused
        end
      end
    end.map(&:value)
    assert_equal %i[billed refused], results.sort
    assert_equal 1, as_business(business) { InvoiceLineItem.final_bills.where(job_line_item_id: job.line_items.ids).count }
  ensure
    if job
      as_business(business) do
        client_id = job.client_id
        Invoice.where(client_id:).find_each(&:destroy!)
        JobClaim.where(job_id: job.id).delete_all
        WorkEntry.where(job_id: job.id).delete_all
        Visit.where(job_id: job.id).delete_all
        Job.where(id: job.id).delete_all
        QuoteLineItem.where(quote_id: Quote.where(client_id:).select(:id)).delete_all
        Quote.where(client_id:).delete_all
        Client.find(client_id).destroy!
      end
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end

# B2: a payment takes the quote's lock before the invoice's, as void, draft saves and billing do,
# so a payment and a void (or a bill) can't wait on each other.
class InvoiceLockOrderTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "a card payment waits on the quote's lock without holding the invoice's" do
    business = businesses(:one)
    invoice = as_business(business) do
      client = Client.create!(display_name: "Lock order", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "t", "name" => "Trees", "quantity" => "10", "unit_price" => "100" } ])
        _1.save!
        _1.update_columns(status: "approved")
      end
      Invoice.from_quote!(quote).tap { _1.mark_sent!(by: nil, channel: "link") }
    end
    holding = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        as_business(business) do
          Invoice.transaction do
            QuoteWork.lock!(invoice.quote_id)
            holding << true
            release.pop
            Invoice.lock("FOR UPDATE NOWAIT").find(invoice.id) && :invoice_free
          end
        end
      end
    end
    holding.pop
    payer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        as_business(business) { Invoice.find(invoice.id).record_online_payment!(intent_id: "pi_order", amount_cents: 1_000, currency: "usd").second }
      end
    end
    sleep 0.5 # the payment is now waiting on the quote
    release << true
    assert_equal :invoice_free, holder.value, "the payment hadn't taken the invoice's lock while waiting"
    assert payer.value
  ensure
    if invoice
      as_business(business) do
        client_id = invoice.client_id
        Payment.where(invoice_id: invoice.id).delete_all
        JobClaim.where(invoice_line_item_id: InvoiceLineItem.where(invoice_id: invoice.id).select(:id)).delete_all
        Invoice.where(client_id:).find_each { _1.events.delete_all && _1.sends.delete_all && _1.line_items.delete_all && _1.delete }
        QuoteLineItem.where(quote_id: Quote.where(client_id:).select(:id)).delete_all
        Quote.where(client_id:).each { _1.events.delete_all if _1.respond_to?(:events) }
        Quote.where(client_id:).delete_all
        ClientEvent.where(client_id:).delete_all
        ClientLink.where(linkable_type: "Invoice", linkable_id: invoice.id).delete_all
        Client.find(client_id).destroy!
      end
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end
