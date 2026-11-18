require "test_helper"

# PAY-02: sending an invoice by email or as a copied link, first views, and delivery problems.
class Admin::InvoiceSendsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @invoice = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      invoice = Invoice.start(client: maria)
      invoice.title = "Spring cleanup"
      invoice.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180", "taxable" => "0" } ])
      invoice.tax_rates = []
      invoice.save!
      invoice
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def fresh = as_business(@business) { @invoice.reload }

  def send_email(**fields)
    post admin_invoice_send_path(@invoice), params: { invoice_send: { to: "maria@example.com", subject: "Your invoice", message: "Hi Maria" }.merge(fields) }
  end

  test "the builder links to sending; the send page prefills the client's email, the subject and a message" do
    get edit_admin_invoice_path(@invoice)
    assert_select "a[href=?]", new_admin_invoice_send_path(@invoice), /Send/
    get new_admin_invoice_send_path(@invoice)
    assert_response :success
    assert_select "input[name='invoice_send[to]'][value='maria@example.com']"
    assert_select "input[name='invoice_send[subject]'][value=?]", "Invoice #{@invoice.number} from #{@business.name}: Spring cleanup"
    assert_select "textarea[name='invoice_send[message]']", /Hi Maria,/
    assert_select "form[action=?] button", admin_invoice_send_path(@invoice), /Get the link/
  end

  test "sending by email marks it sent, records the send and emails the client the link and the PDF" do
    with_fake_pdf_renderer do
      send_email(cc: "partner@example.com")
      assert_redirected_to admin_invoice_path(@invoice)

      invoice = fresh
      assert_equal [ "sent", users(:one) ], [ invoice.status, invoice.sent_by ]
      assert invoice.sent_at
      assert_not invoice.editable?
      send, event = as_business(@business) { [ invoice.sends.first, invoice.events.last ] }
      assert_equal [ "email", "maria@example.com", "partner@example.com", users(:one), 1 ], [ send.channel, send.recipient, send.cc, send.user, send.revision ]
      assert_equal [ "sent", "email" ], [ event.kind, event.data["channel"] ]

      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      assert_equal [ [ "maria@example.com" ], [ "partner@example.com" ], "Your invoice" ], [ mail.to, mail.cc, mail.subject ]
      assert_equal "Invoice #{invoice.number}.pdf", mail.attachments.first.filename
      link = as_business(@business) { ClientLink.active.find_by!(linkable: invoice) }
      assert_nil link.expires_at
      assert_match "/c/#{link.token}", mail.html_part.body.to_s
      assert_match "$180.00", mail.html_part.body.to_s
      assert_match "View invoice", mail.html_part.body.to_s
      assert_match "Hi Maria", mail.text_part.body.to_s
      assert_equal "sent", as_business(@business) { send.reload.email_message.status }

      get admin_invoice_path(@invoice)
      assert_select "#sent-panel-h", /Sent/
      assert_select "li", /Emailed to maria@example.com, cc partner@example.com/
      assert_select "li", /Sent by email by/
    end
  end

  test "sending again records another send; the same link is used" do
    with_fake_pdf_renderer do
      send_email
      sent_at = fresh.sent_at
      get admin_invoice_path(@invoice)
      assert_select "a[href=?]", new_admin_invoice_send_path(@invoice), /Send again/
      send_email(to: "maria.lopez@example.com")
      assert_equal [ 2, sent_at ], [ as_business(@business) { fresh.sends.count }, fresh.sent_at ]
      assert_equal 1, as_business(@business) { ClientLink.where(linkable: @invoice).count }
    end
  end

  test "copy link marks the invoice sent; the page then shows the link to copy" do
    post admin_invoice_send_path(@invoice), params: { channel: "link" }
    assert_redirected_to new_admin_invoice_send_path(@invoice)
    assert_equal "sent", fresh.status
    assert_equal "link", as_business(@business) { fresh.sends.first.channel }
    follow_redirect!
    link = as_business(@business) { ClientLink.active.find_by!(linkable: @invoice) }
    assert_select "input[readonly][value=?]", client_link_url(link.token)
  end

  test "a revision is sent the same way, and the client sees it again" do
    with_fake_pdf_renderer do
      send_email
      link = as_business(@business) { ClientLink.active.find_by!(linkable: @invoice) }
      post revise_admin_invoice_path(@invoice)
      get edit_admin_invoice_path(@invoice)
      assert_select "a[href=?]", new_admin_invoice_send_path(@invoice), /Send revision/
      get client_link_path(link.token)
      assert_select "h1", /is updating this invoice/

      send_email
      assert_equal [ "sent", 2 ], [ fresh.status, fresh.revision ]
      assert_equal [ 2, 1 ], as_business(@business) { fresh.sends.map(&:revision) }
      get client_link_path(link.token)
      assert_select ".quote-doc-kicker", "Invoice #{@invoice.number}"
    end
  end

  test "a bad or refused address is a clear error and nothing is sent" do
    send_email(to: "not-an-email")
    assert_response :unprocessable_content
    assert_select ".field", /isn't a valid email address/
    as_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    send_email
    assert_select ".field", /was refused by the mail server before/
    assert_equal "draft", fresh.status
    assert_no_enqueued_emails
  end

  test "empty, paid and void invoices aren't sent" do
    as_business(@business) { @invoice.line_items.delete_all }
    get new_admin_invoice_send_path(@invoice)
    assert_redirected_to edit_admin_invoice_path(@invoice)
    assert_equal "Add at least one line before sending.", flash[:alert]

    as_business(@business) { @invoice.update_columns(status: "paid", sent_at: Time.current) }
    as_business(@business) { @invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "5" } ]) && @invoice.save! }
    post admin_invoice_send_path(@invoice), params: { channel: "link" }
    assert_redirected_to admin_invoice_path(@invoice)
    assert_match "is paid", flash[:alert]
    as_business(@business) { @invoice.update_columns(status: "void") }
    get new_admin_invoice_send_path(@invoice)
    assert_match "is void", flash[:alert]
  end

  test "an invoice that doesn't validate is sent back to the builder" do
    as_business(@business) { @invoice.update_columns(title: "x" * 300) }
    post admin_invoice_send_path(@invoice), params: { channel: "link" }
    assert_redirected_to edit_admin_invoice_path(@invoice)
    assert_match "Fix the invoice before sending", flash[:alert]
    assert_equal "draft", fresh.status
  end

  test "an unconfirmed account can see the page but can't send" do
    unconfirmed = users(:unconfirmed)
    BusinessUser.create!(user: unconfirmed, business: @business, role: "admin", active: true)
    sign_in unconfirmed
    post switch_admin_business_path, params: { business: @business.uid }
    get new_admin_invoice_send_path(@invoice)
    assert_select ".banner-warning", /Confirm your email address/
    send_email
    assert_match "Confirm your email address", flash[:alert]
    post admin_invoice_send_path(@invoice), params: { channel: "link" }
    assert_equal "draft", fresh.status
  end

  test "technicians can't send; other businesses' invoices aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_invoice_send_path(@invoice) }
    assert_permission_matrix(technician: false) { post admin_invoice_send_path(@invoice), params: { channel: "link" } }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      Invoice.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ]))
    end
    assert_not_found_across_businesses { get new_admin_invoice_send_path(theirs) }
    assert_not_found_across_businesses { post admin_invoice_send_path(theirs), params: { channel: "link" } }
  end

  test "a bounce shows on the invoice" do
    with_fake_pdf_renderer do
      send_email
      as_business(@business) { @invoice.sends.first.email_message.mark!("bounced", error: "The mail server refused this address (550 5.1.1).") }
      get admin_invoice_path(@invoice)
      assert_select "#invoice-delivery-problem", /wasn't delivered: The mail server refused this address/
    end
  end

  test "an invoice can be emailed at most five times a day" do
    with_fake_pdf_renderer do
      5.times { |i| send_email(to: "maria#{i}@example.com") }
      send_email
      assert_response :unprocessable_content
      assert_select "[role=alert]", /emailed 5 times today/
    end
  end

  test "the client's views are recorded, and the first one tells the office" do
    post admin_invoice_send_path(@invoice), params: { channel: "link" }
    link = as_business(@business) { ClientLink.active.find_by!(linkable: @invoice) }
    sign_out :user
    2.times { get client_link_path(link.token) }
    assert_equal 2, as_business(@business) { link.reload.views_count }
    notes = as_business(@business) { Notification.where(kind: "invoice_viewed").to_a }
    assert notes.any?
    assert_equal [ "Maria Lopez opened invoice #{@invoice.number}" ], notes.map(&:title).uniq
    assert_equal admin_invoice_path(@invoice), notes.first.path
  end
end
