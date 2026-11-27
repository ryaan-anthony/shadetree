require "test_helper"

# PAY-06: the quote page's Primary (Create invoice while completed work is
# unbilled, else Create job), the job page's Create invoice, refusals with their reason, an invoice
# over several jobs, roles and tenancy.
class Admin::BillingCompletedWorkTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: users(:one))
      quote.title = "Yard work"
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100" },
                              { "key" => "g", "name" => "Gutters", "quantity" => "1", "unit_price" => "200" } ])
      quote.save!
      quote.update_columns(status: "approved")
      quote
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def make(trees: nil, gutters: nil)
    as_business(@business) do
      picks = { "t" => trees, "g" => gutters }.compact.to_h { |key, quantity| [ @quote.line_items.find_by!(key:).id, quantity.to_s ] }
      Job.from_quote!(@quote.reload, picks:)
    end
  end

  def complete(job)
    as_business(@business) { job.reload.complete!(by: users(:one)) }
    job
  end

  test "the quote page: Create job while nothing is done, Create invoice once completed work is unbilled, neither once all is billed" do
    trees = make(trees: 10)
    get admin_quote_path(@quote)
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    assert_select "form[action=?]", admin_quote_invoices_path(@quote), count: 0

    complete(trees)
    get admin_quote_path(@quote)
    assert_select "form[action=?] button.btn-primary", admin_quote_invoices_path(@quote), /Create invoice/
    assert_select "a.btn-secondary[href=?]", new_admin_quote_job_path(@quote), /Create job/, "the gutters are still to do"

    post admin_quote_invoices_path(@quote)
    invoice = as_business(@business) { Invoice.last }
    assert_redirected_to edit_admin_invoice_path(invoice)
    get admin_quote_path(@quote)
    assert_select "form[action=?]", admin_quote_invoices_path(@quote), count: 0
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    assert_select "a#quote-invoice-link[href=?]", admin_invoice_path(invoice)

    post admin_quote_invoices_path(@quote)
    assert_redirected_to admin_quote_path(@quote)
    assert_equal "Couldn't start an invoice: Everything done on #{@quote.number} is billed.", flash[:alert]
  end

  test "with every job cancelled the quote is billed directly (Secondary), and there's no Reopen job" do
    job = make(trees: 4)
    as_business(@business) { job.cancel!(by: users(:one), notify_client: false) }
    get admin_quote_path(@quote)
    assert_select "form[action=?]", reopen_admin_job_path(job), count: 0
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    assert_select "form[action=?] button.btn-secondary", admin_quote_invoices_path(@quote), /Create invoice/
  end

  test "the job page offers Create invoice once completed, and a quote invoice over several jobs lists them all" do
    trees, gutters = make(trees: 10), make(gutters: 1)
    get admin_job_path(trees)
    assert_select "#invoices form[action=?]", admin_job_invoices_path(trees), count: 0
    post admin_job_invoices_path(trees)
    assert_redirected_to admin_job_path(trees)
    assert_equal "Couldn't start an invoice: #{trees.number} isn't completed yet. An invoice bills completed work.", flash[:alert]

    [ trees, gutters ].each { complete(_1) }
    get admin_job_path(trees)
    assert_select ".banner-success", /Ready to invoice/
    post admin_quote_invoices_path(@quote)
    invoice = as_business(@business) { Invoice.last }
    get edit_admin_invoice_path(invoice)
    assert_select "a[href=?]", admin_job_path(trees), trees.number
    assert_select "a[href=?]", admin_job_path(gutters), gutters.number
    get admin_job_path(gutters)
    assert_select ".banner-success", text: /Ready to invoice/, count: 0
    assert_select "#invoices a[href=?]", edit_admin_invoice_path(invoice)
    assert_select "#invoices form[action=?]", admin_job_invoices_path(gutters), count: 0
  end

  test "technicians and members who quote their requests (QTE-07/08) can't invoice" do
    job = complete(make(trees: 10))
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_job_invoices_path(job) }
    assert_permission_matrix(technician: false) { post admin_quote_invoices_path(@quote) }
    sign_out :user
    as_technician do
      post admin_quote_invoices_path(@quote)
      assert_response :forbidden
    end
  end

  test "another business's quotes and jobs aren't found" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Zed", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs")
    end
    assert_not_found_across_businesses { post admin_job_invoices_path(theirs) }
    their_quote = as_business(businesses(:two)) { Quote.create!(client: theirs.client, title: "Theirs") }
    assert_not_found_across_businesses { post admin_quote_invoices_path(their_quote) }
  end

  test "the quote page's billing checks don't grow with its jobs" do
    count = lambda do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get admin_quote_path(@quote) }
      assert_response :success
      queries
    end
    2.times { complete(make(trees: 1)) }
    with_two = count.call
    3.times { complete(make(trees: 1)) }
    assert_equal with_two, count.call
  end

  test "the direct Create invoice is hidden once every line still to do already has a direct bill" do
    post admin_quote_invoices_path(@quote)
    invoice = as_business(@business) { Invoice.last }
    as_business(@business) do # 3 trees lowered off the draft: to do, for a job, but not billed directly again
      invoice.sync_line_items(invoice.line_items.map { { "key" => _1.key, "name" => _1.name, "quantity" => (_1.name == "Tree removal" ? "7" : _1.quantity).to_s, "unit_price" => _1.unit_price.to_s } })
      invoice.save!
    end
    get admin_quote_path(@quote)
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    assert_select "form[action=?]", admin_quote_invoices_path(@quote), count: 0
  end

  test "the editor marks a line taxed at its own job's rates" do
    trees, gutters = make(trees: 10), make(gutters: 1)
    as_business(@business) { gutters.update_columns(tax_rates: [ { "name" => "County", "percent" => "5" } ]) }
    [ trees, gutters ].each { complete(_1) }
    post admin_quote_invoices_path(@quote)
    invoice = as_business(@business) { Invoice.last }
    get edit_admin_invoice_path(invoice)
    gutters_key = as_business(@business) { invoice.line_items.find_by!(name: "Gutters").key }
    assert_select "#line-taxes-#{gutters_key}", /Taxed at its job's rates: County 5%/
    assert_select "[id^='line-taxes-']", count: 1
  end
end
