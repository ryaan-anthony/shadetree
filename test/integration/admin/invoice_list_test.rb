require "test_helper"

# PAY-01: the invoice list (tabs, search, what's outstanding and overdue), revising and voiding
# sent invoices, and the files the client sees (uploads and the job's photos).
class Admin::InvoiceListTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", invoice_due_days: 30)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    @today = @business.today
    as_business(@business) do
      @maria = client("Maria Lopez")
      @sam = client("Sam Okafor")
      @draft = invoice(@maria, 100)
      @sent = invoice(@maria, 200, status: "sent", due_on: @today + 5)
      @late = invoice(@sam, 300, status: "partially_paid", paid: 50, due_on: @today - 3)
      @paid = invoice(@sam, 400, status: "paid", paid: 400, due_on: @today - 10)
      @void = invoice(@sam, 500, status: "void", due_on: @today - 10)
    end
  end

  def client(name) = Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: "555010#{name.length}00" } ])

  def invoice(client, dollars, status: "draft", paid: 0, due_on: nil)
    Invoice.start(client:).tap do |invoice|
      invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => dollars.to_s } ])
      invoice.update!(tax_rates: [])
      invoice.update_columns(status:, amount_paid_cents: paid * 100, sent_at: (Time.current unless status == "draft"), **({ due_on:, issued_on: [ due_on, @today ].min - 1 } if due_on).to_h)
    end
  end

  def fresh(record) = as_business(@business) { yield record.reload }

  test "the list: tabs with counts, outstanding and overdue totals, overdue flagged" do
    get admin_invoices_path
    assert_select "nav.tabs button[value=all]", /All\s+5/
    assert_select "nav.tabs button[value=outstanding]", /Awaiting payment\s+2/
    assert_select "nav.tabs button[value=overdue]", /Overdue\s+1/
    assert_select "#invoice-totals", /5 invoices.*Outstanding \$450\.00.*overdue \$250\.00/m
    assert_select "tr#invoice-#{@late.uid}", /Partly paid.*Overdue.*\$300\.00.*\$250\.00/m
    assert_select "tr#invoice-#{@draft.uid} a[href=?]", edit_admin_invoice_path(@draft)
    assert_select "a[href=?]", admin_invoices_path, text: /Invoices/

    post search_admin_invoices_path, params: { filter: "overdue" }
    assert_select "tbody tr", 1
    assert_select "#invoice-totals", /1 invoice.*Outstanding \$250\.00/m
    post search_admin_invoices_path, params: { filter: "all", q: "okafor" }
    assert_select "tbody tr", 3
    post search_admin_invoices_path, params: { filter: "all", q: @sent.number }
    assert_select "tbody tr", 1
    post search_admin_invoices_path, params: { filter: "paid", q: "nobody" }
    assert_select "turbo-frame#invoice_results", /No invoices match/
  end

  test "technicians can't see the list; it only holds this business's invoices" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_invoices_path }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    as_business(businesses(:two)) { invoice(Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550109999" } ]), 999) }
    get admin_invoices_path
    assert_select "nav.tabs button[value=all]", /All\s+5/
    assert_no_match "$999.00", response.body
  end

  test "a sent invoice is revised: what was sent is kept, and it reopens as the next revision's draft" do
    get admin_invoice_path(@sent)
    assert_select "form[action=?]", revise_admin_invoice_path(@sent)
    post revise_admin_invoice_path(@sent)
    assert_redirected_to edit_admin_invoice_path(@sent)
    assert_equal [ "draft", 2, [ 1 ] ], fresh(@sent) { [ _1.status, _1.revision, _1.revisions.map(&:number) ] }
    follow_redirect!
    assert_select ".banner-info", /Revising what was sent as revision 1 \(\$200\.00\)/
    assert_select "form[action=?]", admin_invoice_path(@sent) # the builder
    delete admin_invoice_path(@sent)
    assert_match "never sent", flash[:alert], "it went out, so it's kept"

    post revise_admin_invoice_path(@late)
    assert_match "it has payments", flash[:alert]
  end

  test "voiding needs a reason; an invoice with payments, or a draft, can't be voided" do
    patch void_admin_invoice_path(@sent), params: { reason: " " }
    assert_match "Say why", flash[:alert]
    patch void_admin_invoice_path(@sent), params: { reason: "Billed twice" }
    assert_equal [ "void", "Billed twice", @owner ], fresh(@sent) { [ _1.status, _1.void_reason, _1.voided_by ] }
    get admin_invoice_path(@sent)
    assert_select ".banner-warning", /Voided .* by .*“Billed twice”/
    assert_select "li", /Voided by .*“Billed twice”/

    patch void_admin_invoice_path(@late), params: { reason: "Oops" }
    assert_match "while it has payments", flash[:alert]
    patch void_admin_invoice_path(@draft), params: { reason: "Oops" }
    assert_equal "draft", fresh(@draft, &:status)
  end

  test "files: uploads and the job's visit photos are attached; removing one unlinks it" do
    job, photo = as_business(@business) do
      job = Job.create!(client: @maria, title: "Spring cleanup", line_items_attributes: [ { name: "Mowing", quantity: 1, unit_price: "50" } ])
      visit = job.visits.new(scheduled_on: @today, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
      visit.photos.attach(io: file_fixture("logo.png").open, filename: "after.png", content_type: "image/png")
      [ job, visit.photos.attachments.first ]
    end
    invoice = as_business(@business) { Invoice.from_job!(job) }
    get edit_admin_invoice_path(invoice)
    assert_select "input[type=checkbox][name='invoice[job_photos][]'][value=?]", photo.id.to_s
    assert_select "input[type=file][name='invoice[attachments][]']"

    patch admin_invoice_path(invoice), params: { invoice: { lock_version: invoice.lock_version, job_photos: [ photo.id, photo.id ],
                                                            attachments: [ fixture_file_upload("logo.png", "image/png") ] } }
    assert_redirected_to edit_admin_invoice_path(invoice)
    files = fresh(invoice) { _1.attachments.to_a }
    assert_equal 2, files.size
    assert_includes files.map(&:blob_id), photo.blob_id, "the visit's stored photo, shared"
    follow_redirect!
    assert_select "input[name='invoice[job_photos][]']", 0, "already attached"

    other = as_business(@business) { Invoice.start(client: @maria) }
    patch admin_invoice_path(other), params: { invoice: { lock_version: other.lock_version, job_photos: [ photo.id ] } }
    assert_empty fresh(other) { _1.attachments.to_a }, "only the invoice's own job's photos"

    shared = files.find { _1.blob_id == photo.blob_id }
    delete admin_invoice_attachment_path(invoice, shared)
    assert_equal 1, fresh(invoice) { _1.attachments.count }
    assert as_business(@business) { photo.reload.blob.persisted? }, "the visit keeps its photo"
  end
end
