require "test_helper"

# PAY-08 (split_jobs flag): progress invoices from a job or a quote before the work is done,
# credited on the final bill; roles and tenancy.
class Admin::ProgressBillingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: users(:one))
      quote.title = "Roof"
      quote.sync_line_items([ { "key" => "r", "name" => "Roof", "quantity" => "1", "unit_price" => "1000" } ])
      quote.save!
      quote.update_columns(status: "approved")
      quote
    end
    enable_feature(:split_jobs)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def make = as_business(@business) { Job.from_quote!(@quote.reload, picks: { @quote.line_items.sole.id => "1" }) }

  test "a progress invoice from an open job, lowered, then credited on the job's final invoice" do
    job = make
    post admin_job_invoices_path(job, progress: 1)
    invoice = as_business(@business) { Invoice.last }
    assert_redirected_to edit_admin_invoice_path(invoice)
    assert_equal "Progress invoice #{invoice.number} started from job #{job.number}.", flash[:notice]
    assert_equal [ "progress", 1000_00 ], [ invoice.kind, invoice.total_cents ]

    line = as_business(@business) { invoice.line_items.sole }
    patch admin_invoice_path(invoice), params: { invoice: { lines_present: "1", lines: { "0" => { key: line.key, name: "Roof", quantity: "1", unit_price: "1200" } } } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_match "Roof: only $1,000.00 is left to bill.", response.body

    as_business(@business) do
      invoice.reload.line_items.sole.update!(unit_price: "400")
      invoice.reload.save!
      invoice.mark_sent!(by: users(:one), channel: "link")
      job.reload.complete!(by: users(:one))
    end
    post admin_job_invoices_path(job)
    final = as_business(@business) { Invoice.last }
    assert_equal [ "work", 600_00 ], [ final.kind, final.total_cents ]
  end

  test "a quote's progress invoice bills what isn't done; with nothing left it's refused, saying why" do
    post admin_quote_invoices_path(@quote, progress: 1)
    invoice = as_business(@business) { Invoice.last }
    assert_equal [ "progress", @quote.id, 1000_00 ], [ invoice.kind, invoice.quote_id, invoice.total_cents ]
    post admin_quote_invoices_path(@quote, progress: 1)
    assert_redirected_to admin_quote_path(@quote)
    assert_equal "Couldn't start an invoice: Nothing on #{@quote.number} is left to bill as progress.", flash[:alert]
  end

  test "technicians can't bill progress" do
    job = make
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_job_invoices_path(job, progress: 1) }
    assert_permission_matrix(technician: false) { post admin_quote_invoices_path(@quote, progress: 1) }
  end

  test "another business's jobs and quotes aren't found for progress billing" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Zed", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs")
    end
    assert_not_found_across_businesses { post admin_job_invoices_path(theirs, progress: 1) }
    their_quote = as_business(businesses(:two)) { Quote.create!(client: theirs.client, title: "Theirs") }
    assert_not_found_across_businesses { post admin_quote_invoices_path(their_quote, progress: 1) }
  end

  test "the pages: progress buttons before the work is done; credits and the share on the invoice; progress, with tax" do
    as_business(@business) { @quote.update_columns(discount_kind: "amount", discount_amount_cents: 100_00, tax_rates: [ { "name" => "State", "percent" => "10" } ]) }
    get admin_quote_path(@quote)
    assert_select "form[action=?] button#quote-progress-invoice", admin_quote_invoices_path(@quote, progress: 1), /Create progress invoice/
    job = make
    get admin_job_path(job)
    assert_select "button#job-progress-invoice", /Create progress invoice/
    assert_select "#job-progress-invoice-dialog form[action=?]", admin_job_invoices_path(job, progress: 1) do
      assert_select "label", /Quote discount: \$100\.00 left\. Apply now/
      assert_select "button[data-action=\"fill#fill\"]", "Apply all"
    end

    early = as_business(@business) do
      WorkBilling.bill_progress!(job, by: users(:one)).tap do |invoice|
        assert_equal [ 900_00, 990_00 ], [ invoice.subtotal_cents, invoice.total_cents ], "at most what's left after the discount's share (owner, 2026-11-23)"
        invoice.mark_sent!(by: users(:one), channel: "link")
      end
    end
    get admin_invoice_path(early)
    assert_select "#invoice-progress", /Progress invoice/
    as_business(@business) { job.reload.complete!(by: users(:one)) }
    get admin_job_path(job)
    assert_select "#job-progress-invoice", count: 0, text: nil
    assert_select "#job-progress", /Progress billed\s*\$990\.00/

    post admin_job_invoices_path(job)
    final = as_business(@business) { Invoice.last }
    get edit_admin_invoice_path(final)
    assert_select "#quote_totals .quote-totals-credit", /Billed earlier on #{early.number}\s*−\$900\.00/
    assert_select "#quote_totals", /Quote discount\s*−\$100\.00/
    assert_equal 0, final.total_cents
    as_business(@business) { final.reload.mark_sent!(by: users(:one), channel: "link") }

    get admin_quote_path(@quote)
    assert_select "#quote-progress", /Credited on final invoices\s*\$990\.00/
    assert_select "#quote-progress", text: /Over-billed/, count: 0
    assert_select "#quote-progress-invoice", count: 0
    get admin_invoice_path(early)
    assert_select "#invoice-credited", /credited on #{final.number}/
    assert_select "#invoice-void", count: 0

    get client_link_path(as_business(@business) { final.client_link! }.token)
    assert_select ".quote-doc-totals", /Credit from #{early.number}\s*−\$990\.00/, "with the tax the client paid (owner, 2026-11-23)"
    assert_select ".quote-doc-totals", text: /Billed earlier/, count: 0
    get client_link_path(as_business(@business) { early.client_link! }.token)
    assert_select ".quote-doc-kicker", "Progress invoice #{early.number}"
  end

  test "the client's Credit from rows are what each progress invoice charged, with taxed and untaxed work mixed" do
    quote = as_business(@business) do
      @quote.update_columns(tax_rates: [ { "name" => "State", "percent" => "10" } ])
      @quote.line_items.build(key: "g", name: "Gutters", quantity: 1, taxable: false, position: 1).tap { _1.unit_price = "500" }.save!
      @quote.reload
    end
    job = as_business(@business) { Job.from_quote!(quote, picks: quote.line_items.to_h { [ _1.id, "1" ] }) }
    numbers = %w[Roof Gutters].map do |name|
      as_business(@business) do
        invoice = WorkBilling.bill_progress!(job.reload, by: users(:one))
        invoice.line_items.each { _1.name == name ? _1.assign_attributes(quantity: 1, unit_price: "500") : _1.mark_for_destruction }
        invoice.save!
        invoice.mark_sent!(by: users(:one), channel: "link")
        invoice.number
      end
    end
    as_business(@business) { job.reload.complete!(by: users(:one)) }
    post admin_job_invoices_path(job)
    final = as_business(@business) { Invoice.last.tap { _1.mark_sent!(by: users(:one), channel: "link") } }
    get client_link_path(as_business(@business) { final.client_link! }.token)
    assert_select ".quote-doc-totals", /Credit from #{numbers.first}\s*−\$550\.00/, "the roof's $500 with its 10%"
    assert_select ".quote-doc-totals", /Credit from #{numbers.last}\s*−\$500\.00/, "the gutters, untaxed"
  end

  test "the quote and job pages don't query once per progress invoice" do
    job = make
    count = lambda do |path|
      get path # warms up
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path }
      assert_response :success
      queries
    end
    bill = lambda do
      as_business(@business) do
        invoice = WorkBilling.bill_progress!(job.reload, by: users(:one))
        invoice.line_items.sole.update!(unit_price: "10")
        invoice.reload.save!
        invoice.mark_sent!(by: users(:one), channel: "link")
      end
    end
    2.times { bill.() }
    few = [ admin_quote_path(@quote), admin_job_path(job) ].map { count.(_1) }
    10.times { bill.() }
    many = [ admin_quote_path(@quote), admin_job_path(job) ].map { count.(_1) }
    puts "queries #{few} -> #{many}" if ENV["SHOW_QUERIES"]
    few.zip(many).each { |before, after| assert_operator after - before, :<=, 2, "#{before} queries with 2 progress invoices, #{after} with 12" }
  end

  test "the quote's discount: chosen when creating, changed on the draft, Apply all, and the minimum explained" do
    as_business(@business) do
      @quote.line_items.build(key: "g", name: "Gutters", quantity: 1, position: 1).tap { _1.unit_price = "100" }.save!
      @quote.update_columns(discount_kind: "amount", discount_amount_cents: 300_00)
    end
    roof, gutters = as_business(@business) { @quote.reload.line_items.map { |line| Job.from_quote!(@quote.reload, picks: { line.id => "1" }) } }
    as_business(@business) { roof.reload.complete!(by: users(:one)) }
    post admin_job_invoices_path(roof, discount: "250")
    invoice = as_business(@business) { Invoice.last }
    assert_equal 250_00, invoice.quote_discount_share_cents
    get edit_admin_invoice_path(invoice)
    assert_select "#quote_discount_field label", /Quote discount: \$300\.00 left\. Apply now/
    assert_select "#invoice_quote_discount_applied[value=?]", "250.00"

    patch admin_invoice_path(invoice), params: { invoice: { quote_discount_applied: "0" } }, as: :turbo_stream
    assert_equal 200_00, invoice.reload.quote_discount_share_cents, "held to the minimum"
    assert_match "At least $200.00 now; there's only $100.00 of work left.", response.body
    patch admin_invoice_path(invoice), params: { invoice: { quote_discount_applied: "all" } }
    assert_equal 300_00, invoice.reload.quote_discount_share_cents
    assert gutters
  end
end
