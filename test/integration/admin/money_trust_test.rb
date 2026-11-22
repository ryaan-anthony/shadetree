require "test_helper"

# #289 (admin UX review), trust and money: no obvious second invoice, a client's emails are
# their own, no accidental $0.00 sends, an honest tax total, plain quota wording, and a copy of
# an approved quote.
class Admin::MoneyTrustTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def quote_for(client_name, price: "100", email: "shared@example.com", lines: nil)
    as_business(@business) do
      client = Client.create!(display_name: client_name, contact_methods_attributes: [ { kind: "email", value: email } ])
      Quote.start(client:).tap do |quote|
        quote.sync_line_items(lines || [ { "key" => "a", "name" => "Ant treatment", "quantity" => "1", "unit_price" => price, "taxable" => "1" } ])
        quote.save!
      end
    end
  end

  def approve(quote)
    as_business(@business) do
      quote.mark_sent!(by: @owner, channel: "link")
      quote.record_response!(:approve, by: @owner, signer_name: "Grace", message: "Approved on the phone")
      quote.reload
    end
  end

  test "an invoiced quote links to its invoice; another invoice is only in the menu, with a confirm" do
    quote = approve(quote_for("Grace Chen"))
    get admin_quote_path(quote)
    assert_select "form[action=?] button", admin_quote_invoices_path(quote), text: /Create invoice/

    invoice = as_business(@business) { Invoice.from_quote!(quote, by: @owner) }
    get admin_quote_path(quote)
    assert_select "a#quote-invoice-link[href=?]", admin_invoice_path(invoice), text: /Invoice #{invoice.number}/
    assert_select "form[action=?]", admin_quote_invoices_path(quote), 1, "only the menu's"
    assert_select ".menu form[action=?][data-turbo-confirm*=?] button", admin_quote_invoices_path(quote), invoice.number, text: /Create another invoice/
  end

  test "a job with an invoice offers only 'Create another invoice', with a confirm" do
    quote = approve(quote_for("Grace Chen"))
    job = as_business(@business) { Job.from_quote!(quote, by: @owner) }
    get admin_job_path(job)
    assert_select "#invoices form[action=?]:not([data-turbo-confirm]) button", admin_job_invoices_path(job), text: /Create invoice/
    as_business(@business) { Invoice.from_job!(job, by: @owner) }
    get admin_job_path(job)
    assert_select "#invoices form[action=?][data-turbo-confirm] button", admin_job_invoices_path(job), text: /Create another invoice/
  end

  test "a client's recent emails are about their own records, not everyone at the same address" do
    mama = quote_for("Mama")
    test_customer = quote_for("Test Customer")
    with_fake_pdf_renderer do
      post admin_quote_send_path(mama), params: { quote_send: { to: "shared@example.com", subject: "Mama's quote", message: "Hi" } }
    end
    get admin_client_path(mama.client)
    assert_select "[id^=email-]", 1
    get admin_client_path(test_customer.client)
    assert_select "[id^=email-]", 0, "the same address, but not this client's email"
  end

  test "a $0.00 quote waits for 'Send it at $0.00', and says which lines have no price" do
    quote = quote_for("Maria", price: "0", lines: [ { "key" => "a", "name" => "Termite inspection", "quantity" => "1", "unit_price" => "0" } ])
    get new_admin_quote_send_path(quote)
    assert_select "#zero-total-warning", /comes to \$0\.00.*No price yet on Termite inspection/m
    assert_select "form[action=?]", admin_quote_send_path(quote), 0, "no way to send until it's confirmed"

    post admin_quote_send_path(quote), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(quote)
    assert as_business(@business) { quote.reload.draft? }, "not sent without confirming"

    get new_admin_quote_send_path(quote, zero_total: "confirmed")
    assert_select "#zero-total-warning", 0
    assert_select "input[type=hidden][name=zero_total][value=confirmed]"
    post admin_quote_send_path(quote), params: { channel: "link", zero_total: "confirmed" }
    assert_equal "sent", as_business(@business) { quote.reload.status }
  end

  test "a line without a price is named on the send page even when the total isn't zero" do
    quote = quote_for("Maria", lines: [ { "key" => "a", "name" => "Spraying", "quantity" => "1", "unit_price" => "80" },
                                        { "key" => "b", "name" => "Termite inspection", "quantity" => "1", "unit_price" => "0" } ])
    get new_admin_quote_send_path(quote)
    assert_select "#unpriced-lines", /No price on Termite inspection, so it shows as \$0\.00/
    assert_select "form[action=?]", admin_quote_send_path(quote)
  end

  test "a $0.00 invoice waits for confirmation too" do
    quote = approve(quote_for("Grace", price: "0"))
    invoice = as_business(@business) { Invoice.from_quote!(quote, by: @owner) }
    get new_admin_invoice_send_path(invoice)
    assert_select "#zero-total-warning", /comes to \$0\.00/
    post admin_invoice_send_path(invoice), params: { channel: "link" }
    assert_redirected_to new_admin_invoice_send_path(invoice)
    assert as_business(@business) { invoice.reload.draft? }
  end

  test "with no tax rate, 'Taxed' is hidden and Totals says how to add one" do
    quote = quote_for("Maria")
    get edit_admin_quote_path(quote)
    assert_select "label[hidden] input[type=checkbox][data-field=taxable]"
    assert_select "#no-tax-rates", /No sales tax on this quote\. If you charge it, add your tax rate in Settings/
    assert_select "#no-tax-rates a[href=?]", admin_tax_rates_path

    as_business(@business) { TaxRate.create!(name: "State", percent: "6.25", applies_by_default: true) }
    get edit_admin_quote_path(quote)
    assert_select "label:not([hidden]) input[type=checkbox][data-field=taxable]"
    assert_select "#no-tax-rates", 0
  end

  test "an approved quote can be sent again as a copy: it stays approved and isn't counted" do
    quote = approve(quote_for("Grace", email: "grace@example.com"))
    # The worst case: no usage event and no first quote yet (a quote approved some other way).
    as_business(@business) do
      UsageEvent.where(subject: quote).delete_all
      AutomationRule.create!(name: "On send", trigger: "quote_sent", delay_minutes: 0, conditions: {}, actions: [ { "type" => "notify_team", "team" => "office" } ])
    end
    @business.update_columns(first_quote_sent_at: nil)
    used = as_business(@business) { Entitlements.for(@business).used(:quotes_sent) }
    get admin_quote_path(quote)
    assert_select "a[href=?]", new_admin_quote_send_path(quote), text: /Send again/

    get new_admin_quote_send_path(quote)
    assert_select "h1", /Send a copy of quote #{quote.number}/
    assert_select "input[name='quote_send[subject]'][value=?]", "Your approved quote #{quote.number} from #{@business.name}"
    assert_select "textarea[name='quote_send[message]']", /a copy of the quote you approved/
    assert_select "#quote-usage", 0

    with_fake_pdf_renderer do
      post admin_quote_send_path(quote), params: { quote_send: { to: "grace@example.com", subject: "Your copy", message: "Here it is" } }
      assert_redirected_to admin_quote_path(quote)
      perform_enqueued_jobs
    end
    assert_equal "approved", as_business(@business) { quote.reload.status }
    assert_equal used, as_business(@business) { Entitlements.for(@business).used(:quotes_sent) }, "a copy is never usage"
    assert_nil @business.reload.first_quote_sent_at, "nor a first quote"
    assert_equal 0, as_business(@business) { AutomationRun.count }, "nor does it start quote-sent automations"
    assert_match(/Approved/, ActionMailer::Base.deliveries.last.text_part.body.to_s)
    get admin_quote_path(quote)
    assert_select "#quote-activity", /Copy of approved quote emailed to grace@example\.com/
    get admin_client_path(as_business(@business) { quote.client })
    assert_select "#client-timeline", /Copy of approved quote #{quote.number} sent by email/
  end

  test "an archived approved quote isn't sent again" do
    quote = approve(quote_for("Grace"))
    as_business(@business) { quote.update!(archived_at: Time.current) }
    get new_admin_quote_send_path(quote)
    assert_redirected_to admin_quote_path(quote)
  end

  test "quota wording names the plan and the period" do
    helper = ApplicationController.new.view_context
    as_business(@business) do
      assert_equal "0 of your 5 free quotes this month", helper.quote_allowance(@business.entitlements)
      @business.update!(plan: plans(:starter))
      assert_match(/\A0 of your 30 Starter quotes this (month|billing period)\z/, helper.quote_allowance(Entitlements.for(@business)))
    end
  end
end
