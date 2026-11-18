require "test_helper"

# PAY-02: the client's invoice page through its link, the PDF (client and staff), files served
# through the link, the "being updated" page while it's revised, and the staff preview.
class Client::InvoicePageTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com", phone: "555-380-0000", timezone: "America/New_York")
    @invoice = as_business(@business) do
      TaxRate.create!(name: "State", percent: "6.25")
      maria = Client.create!(display_name: "Maria Lopez", company_name: "Lopez Rentals", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true } ])
      invoice = Invoice.start(client: maria)
      invoice.assign_attributes(title: "Spring cleanup", message: "Thanks for your business.", internal_notes: "Gate code 1234", terms: "Late fee after 30 days.")
      invoice.sync_line_items([
        { "key" => "a", "name" => "Leaf cleanup", "description" => "Front and back yards", "quantity" => "1", "unit_price" => "180", "taxable" => "1" },
        { "key" => "b", "name" => "Mulch", "quantity" => "4", "unit" => "bag", "unit_price" => "8.50", "taxable" => "1" }
      ])
      invoice.attach_files([ Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png", original_filename: "yard.png") ])
      invoice.save!
      invoice.update_columns(status: "sent", sent_at: Time.current)
      invoice
    end
    @link = as_business(@business) { @invoice.client_link! }
  end

  def set_invoice(**attributes) = as_business(@business) { @invoice.update_columns(**attributes) }

  def sign_in_staff
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "shows what's owed and when, the document, and none of the internal notes" do
    get client_link_path(@link.token)
    assert_response :success
    assert_select ".client-card", /Amount due.*\$227\.38.*Due/m
    assert_select ".quote-doc-kicker", "Invoice #{@invoice.number}"
    assert_select ".quote-doc-title", "Spring cleanup"
    assert_select ".quote-doc-meta", /Maria Lopez.*Lopez Rentals.*12 Elm St.*Issued.*Due.*Status.*Due/m
    assert_select ".quote-doc-message", "Thanks for your business."
    assert_select ".quote-doc-lines tbody tr", 2
    assert_select "#quote_totals", /Subtotal.*\$214\.00.*State \(6\.25%\).*\$13\.38.*Total.*\$227\.38/m
    assert_select ".quote-doc-terms", /Late fee after 30 days\./
    assert_select "img[alt=yard]"
    assert_select "a[href=?]", client_invoice_pdf_path(@link.token), /Download PDF/
    assert_select "a[href='tel:555-380-0000']"
    assert_no_match "Gate code 1234", response.body
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_nil @link.expires_at, "an unpaid invoice's link doesn't run out"
  end

  test "overdue, partly paid, paid and void each say so" do
    set_invoice(due_on: @business.today - 2, issued_on: @business.today - 30)
    get client_link_path(@link.token)
    assert_select ".text-danger", /Overdue: was due/

    set_invoice(status: "partially_paid", amount_paid_cents: 10_000)
    get client_link_path(@link.token)
    assert_select ".client-card", /Balance due.*\$127\.38/m
    assert_select ".invoice-doc-balance", /Paid.*\$100\.00.*Balance due.*\$127\.38/m

    set_invoice(status: "paid", amount_paid_cents: 22_738)
    get client_link_path(@link.token)
    assert_select ".banner-success", /Paid in full/
    assert_select ".invoice-doc-balance", /Balance due.*\$0\.00/m

    set_invoice(status: "void", amount_paid_cents: 0)
    get client_link_path(@link.token)
    assert_select ".banner-info", /cancelled, so nothing is due/
    assert_select ".invoice-doc-balance", /Nothing due \(void\)/
  end

  test "a draft is never shown; while it's revised the page says it's being updated, without the edits" do
    set_invoice(status: "draft", revision: 2)
    as_business(@business) { @invoice.reload.update!(title: "Unfinished edit") }
    get client_link_path(@link.token)
    assert_response :success
    assert_select "h1", /is updating this invoice/
    assert_no_match "Unfinished edit", response.body
    get client_invoice_pdf_path(@link.token)
    assert_redirected_to client_link_path(@link.token)
    assert_equal 0, as_business(@business) { @link.reload.views_count }, "not a view of the invoice"

    set_invoice(revision: 1)
    assert_not_found_across_businesses { get client_invoice_pdf_path(@link.token) }
    get client_link_path(@link.token)
    assert_response :gone
  end

  test "files go through the link: a revoked link cuts them off, and only this invoice's files" do
    photo = as_business(@business) { @invoice.attachments_attachments.first }
    get client_link_path(@link.token)
    assert_select "img[src=?]", client_invoice_file_path(@link.token, photo, size: "web")
    get client_invoice_file_path(@link.token, photo)
    assert_response :redirect

    other = as_business(@business) do
      Invoice.start(client: @invoice.client).tap { _1.attachments.attach(io: file_fixture("logo.png").open, filename: "x.png", content_type: "image/png") }
    end
    assert_not_found_across_businesses { get client_invoice_file_path(@link.token, as_business(@business) { other.attachments_attachments.first }) }
    as_business(@business) { @link.revoke! }
    get client_invoice_file_path(@link.token, photo)
    assert_response :gone
  end

  test "the PDF: clients through their link (the stored file reused), staff from the invoice; technicians can't" do
    with_fake_pdf_renderer do |calls|
      2.times do
        get client_invoice_pdf_path(@link.token)
        assert_response :success
        assert_equal "application/pdf", response.media_type
        assert_match %(filename="Invoice #{@invoice.number}.pdf"), response.headers["Content-Disposition"]
      end
      assert_equal 1, calls.size, "the stored file is reused"
      assert_match "Invoice #{@invoice.number}", calls.first[:html]
      assert_match "$227.38", calls.first[:html]
      assert_no_match "Gate code 1234", calls.first[:html]

      set_invoice(status: "partially_paid", amount_paid_cents: 10_000)
      get client_invoice_pdf_path(@link.token)
      assert_equal 2, calls.size, "a payment changes the balance on it"
      assert_match "$127.38", calls.last[:html]

      sign_in_staff
      get admin_invoice_path(@invoice)
      assert_select "a[href=?]", pdf_admin_invoice_path(@invoice)
      get pdf_admin_invoice_path(@invoice)
      assert_response :success
      sign_out :user
      assert_permission_matrix(owner: true, admin: true, technician: false) { get pdf_admin_invoice_path(@invoice) }

      sign_in_staff
      theirs = as_business(businesses(:two)) do
        Invoice.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]))
      end
      assert_not_found_across_businesses { get pdf_admin_invoice_path(theirs) }
      assert_not_found_across_businesses { get preview_admin_invoice_path(theirs) }
    end
  end

  test "staff preview a draft as the client will see it; previews aren't views" do
    set_invoice(status: "draft", sent_at: nil)
    sign_in_staff
    get edit_admin_invoice_path(@invoice)
    assert_select "a[href=?]", preview_admin_invoice_path(@invoice), /Preview as client/
    get preview_admin_invoice_path(@invoice)
    assert_response :success
    assert_select ".banner", /Preview.*Back to the invoice/m
    assert_select ".quote-doc-title", "Spring cleanup"
    assert_select "a[href=?]", pdf_admin_invoice_path(@invoice)
    assert_equal 0, as_business(@business) { @link.reload.views_count }
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get preview_admin_invoice_path(@invoice) }
  end
end
