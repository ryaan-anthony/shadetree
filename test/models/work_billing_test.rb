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

  test "split: a completed job's invoice bills its lines as done; an open job and a billed one are refused" do
    enable_feature(:split_jobs)
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

  test "split: the quote's invoice bills every completed job's unbilled lines, again as more finish, alongside a job's own invoice" do
    enable_feature(:split_jobs)
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

  test "split: a quote invoice over jobs with different tax rates keeps each job's rates on its lines" do
    enable_feature(:split_jobs)
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

  test "split: a quote with no jobs is billed directly, so no job can take its work; voiding frees it, and it can be billed again" do
    enable_feature(:split_jobs)
    invoice = bill_quote
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(invoice)
    assert_equal [ 0, 0 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert_raises(Job::NotOpen) { as_business(@business) { Job.from_quote!(@quote.reload) } }
    assert_match "Everything on #{@quote.number} is billed.", assert_raises(WorkBilling::Refused) { bill_quote }.message

    as_business(@business) { invoice.update_columns(sent_at: Time.current, status: "sent") && invoice.reload.void!(reason: "Wrong client", by: @owner) }
    assert_equal [ 10, 1 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(bill_quote)
  end

  test "split: every job cancelled bills the quote directly; a recurring quote isn't billed directly" do
    enable_feature(:split_jobs)
    job = make(t: 4)
    as_business(@business) { job.cancel!(by: @owner, notify_client: false) }
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(bill_quote)

    as_business(@business) { Invoice.where(quote: @quote).find_each(&:destroy!) }
    @quote.define_singleton_method(:recurring?) { true }
    error = assert_raises(WorkBilling::Refused) { as_business(@business) { Invoice.from_quote!(@quote, by: @owner) } } # JOB-10 sets recurring?
    assert_match "is recurring", error.message
  end

  test "deleting a draft frees its lines; a directly billed line follows its quantity on the draft and frees what it drops" do
    enable_feature(:split_jobs)
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
    enable_feature(:split_jobs)
    job = complete(make(t: 10))
    invoice = bill_job(job)
    as_business(@business) do
      invoice.mark_sent!(by: @owner, channel: "link")
      invoice.reload.revise!(by: @owner)
      invoice.sync_line_items([ { "key" => "typed", "name" => "Typed", "quantity" => "1", "unit_price" => "5" } ])
      invoice.save!
      invoice.reload.discard_revision!(by: @owner)
    end
    assert_equal [ [ "Tree removal", 10, true ] ], billed(invoice)
    assert_equal as_business(@business) { job.line_items.sole.id }, as_business(@business) { invoice.line_items.sole.job_line_item_id }
    assert_raises(WorkBilling::Refused) { bill_job(job) }

    as_business(@business) { invoice.reload.void!(reason: "Redo", by: @owner) }
    assert_equal [ [ "Tree removal", 10, true ] ], billed(bill_job(job))
  end

  test "the database refuses a second final bill that got past the lock" do
    enable_feature(:split_jobs)
    job = complete(make(t: 10))
    invoice = bill_job(job)
    copy = as_business(@business) { Invoice.start(client: @quote.client) }
    assert_raises(ActiveRecord::RecordNotUnique) do
      as_business(@business) { InvoiceLineItem.create!(invoice: copy, key: "x", name: "Again", quantity: 1, unit_price: "1", job_line_item_id: invoice.line_items.sole.job_line_item_id, final: true) }
    end
  end

  test "flag off: as before, a job is billed at any status and again, and the quote bills its lines as agreed; repeats are progress" do
    job = as_business(@business) { Job.from_quote!(@quote, by: @owner) }
    first, second = bill_job(job), bill_job(job)
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(first)
    assert_equal [ [ "Tree removal", 10, false ], [ "Gutters", 1, false ] ], billed(second)
    from_quote = bill_quote
    assert_equal [ [ "Tree removal", 10, false ], [ "Gutters", 1, false ] ], billed(from_quote)
    assert_equal as_business(@business) { job.line_items.ids }, as_business(@business) { from_quote.line_items.map(&:job_line_item_id) }
    assert_equal [ first, second, from_quote ].map(&:id), as_business(@business) { job.invoices.order(:id).ids }
  end

  test "flag off: a quote with no job is billed directly, as JOB-09 claimed it; a repeat is progress with no claim" do
    first, second = bill_quote, bill_quote
    assert_equal [ [ "Tree removal", 10, true ], [ "Gutters", 1, true ] ], billed(first)
    assert_equal [ [ "Tree removal", 10, false ], [ "Gutters", 1, false ] ], billed(second)
    assert_equal [ 0, 0 ], [ line("t"), line("g") ].map { _1.to_do_quantity.to_i }
    assert_equal 2, as_business(@business) { JobClaim.where(job_id: nil).count }
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
    Feature.overrides["split_jobs"] = true
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
    Feature.overrides.delete("split_jobs")
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
