require "test_helper"

# PAY-01: starting invoices (from scratch, a job or an approved quote), the builder's autosave,
# and where invoices show (job, quote and client pages).
class Admin::InvoicesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", invoice_due_days: 30)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", billing: true } ])
      @job = Job.create!(client: @maria, property: @maria.properties.first, title: "Spring cleanup",
                         line_items_attributes: [ { name: "Mowing", quantity: 2, unit_price: "45" } ])
    end
  end

  def fresh(record) = as_business(@business) { yield record.reload }

  def builder_params(invoice, lines: [], **fields)
    { invoice: { lock_version: invoice.lock_version, lines_present: "1",
                 lines: lines.each_with_index.to_h { |line, index| [ index.to_s, line ] }, **fields } }
  end

  test "technicians can't see or make invoices; another business's aren't found" do
    invoice = as_business(@business) { Invoice.start(client: @maria) }
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_invoice_path(invoice) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_job_invoices_path(@job) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_invoices_path, params: { invoice: { client: @maria.uid } } }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Invoice.start(client:)
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    assert_not_found_across_businesses { get edit_admin_invoice_path(theirs) }
    assert_not_found_across_businesses { delete admin_invoice_path(theirs) }
  end

  test "from a job: one tap makes a draft with its items, opened in the builder; the job lists it" do
    as_business(@business) { @job.complete!(by: users(:one)) }
    post admin_job_invoices_path(@job)
    invoice = as_business(@business) { Invoice.last }
    assert_redirected_to edit_admin_invoice_path(invoice)
    follow_redirect!
    assert_select "h1", "Invoice #{invoice.number}"
    assert_select "[data-controller=quote-builder][data-quote-builder-scope-value=invoice]"
    assert_select "input[name='invoice[lines][0][name]'][value=Mowing]"
    assert_select "#quote_totals", /Total.*\$90\.00/m
    assert_select "a[href=?]", admin_job_path(@job), text: "job #{@job.number}"
    assert_select "input[name='invoice[client]']", 0, "it bills this job, so it stays with the job's client"

    get admin_job_path(@job)
    assert_select "#invoices #invoice-#{invoice.uid}", /#{invoice.number}.*Draft.*\$90\.00/m
  end

  test "a completed job prompts Create invoice until it has one" do
    as_business(@business) { @job.complete!(by: users(:one)) }
    get admin_job_path(@job)
    assert_select ".banner-success", /Ready to invoice/
    assert_select ".banner-success form[action=?]", admin_job_invoices_path(@job)
    post admin_job_invoices_path(@job)
    get admin_job_path(@job)
    assert_select ".banner-success", text: /Ready to invoice/, count: 0
  end

  test "from an approved quote, linked both ways; not from one that isn't approved" do
    quote = as_business(@business) do
      Quote.start(client: @maria).tap do |q|
        q.sync_line_items([ { "key" => "a", "name" => "Hedge trim", "quantity" => "1", "unit_price" => "80" } ])
        q.save!
      end
    end
    post admin_quote_invoices_path(quote)
    assert_redirected_to admin_quote_path(quote)
    assert_match "Only an approved quote", flash[:alert]

    as_business(@business) { quote.update_columns(status: "approved") }
    get admin_quote_path(quote)
    assert_select "form[action=?]", admin_quote_invoices_path(quote)
    post admin_quote_invoices_path(quote)
    invoice = as_business(@business) { Invoice.last }
    get admin_quote_path(quote)
    assert_select "#invoices #invoice-#{invoice.uid}"
  end

  test "from scratch for a client, from the client page; the client's page lists it and what's owed" do
    get admin_client_path(@maria)
    assert_select "a[href=?]", new_admin_invoice_path(client: @maria.uid)
    get new_admin_invoice_path(client: @maria.uid)
    assert_select "input[type=hidden][name='invoice[client]'][value=?]", @maria.uid
    post admin_invoices_path, params: { invoice: { client: "" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Choose a client/

    post admin_invoices_path, params: { invoice: { client: @maria.uid } }
    invoice = as_business(@business) { Invoice.last }
    assert_redirected_to edit_admin_invoice_path(invoice)
    as_business(@business) do
      invoice.sync_line_items([ { "key" => "a", "name" => "Walk-in repair", "quantity" => "1", "unit_price" => "120" } ])
      invoice.update!(tax_rates: []) # lines go on drafts only (PAY-06)
      invoice.update!(status: "sent", amount_paid_cents: 2000)
    end
    get admin_client_path(@maria)
    assert_select "a[href=?]", admin_invoice_path(invoice), text: /#{invoice.number}/
    assert_select ".card", text: /Balance.*\$100\.00.*Owed on invoices/m
  end

  test "the builder autosaves lines, terms and taxes, answering with totals and the new due date" do
    invoice = as_business(@business) { Invoice.start(client: @maria) }
    lines = [ { key: "k1", name: "Mowing", quantity: "3", unit_price: "40", taxable: "1" } ]
    patch admin_invoice_path(invoice), params: builder_params(invoice, lines:, issued_on: "2026-12-01", payment_terms: "net_7", title: "December"),
                                       as: :turbo_stream
    assert_response :ok
    assert_match "$120.00", response.body
    assert_match "Dec 8", response.body, "the due date from the new terms"
    assert_equal [ "December", Date.new(2026, 12, 8), 12_000 ], fresh(invoice) { [ _1.title, _1.due_on, _1.subtotal_cents ] }

    patch admin_invoice_path(invoice), params: builder_params(invoice.reload, lines:, payment_terms: "custom", due_on: "2027-01-15"), as: :turbo_stream
    assert_equal Date.new(2027, 1, 15), fresh(invoice, &:due_on)
    assert_no_match "invoice[payment_terms]", response.body, "the controls aren't replaced, so edits made during a save stay"

    stale = builder_params(invoice, lines:).deep_merge(invoice: { lock_version: 0 })
    patch admin_invoice_path(invoice), params: stale, as: :turbo_stream
    assert_response :conflict
    assert_match "changed in another tab", response.body
  end

  test "a draft that was never sent can be deleted; a sent one opens its page, not the builder" do
    as_business(@business) { @job.complete!(by: users(:one)) }
    invoice = as_business(@business) { Invoice.from_job!(@job, by: users(:one)) }
    delete admin_invoice_path(invoice)
    assert_redirected_to admin_job_path(@job)
    assert_not as_business(@business) { Invoice.exists?(invoice.id) }

    sent = as_business(@business) { Invoice.from_job!(@job, by: users(:one)).tap { _1.update_columns(status: "sent", sent_at: Time.current) } }
    get edit_admin_invoice_path(sent)
    assert_redirected_to admin_invoice_path(sent)
    get admin_invoice_path(sent)
    assert_select "h1", "Invoice #{sent.number}"
    assert_select "dl", /Sent.*Due.*Within 30 days.*\$90\.00/m
    assert_select "li", /Created from job #{@job.number} by/
    delete admin_invoice_path(sent)
    assert_match "never sent", flash[:alert]
  end
end
