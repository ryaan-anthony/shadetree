require "test_helper"

# #289 (admin UX review), visual polish: long forms have what they're about beside them, the
# builders save one way (as you go), and a flow's buttons keep their words.
class Admin::FormPolishTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "2155551212" } ])
      @job = Job.create!(client: @maria, title: "Ants", instructions: "Side gate", line_items_attributes: [ { name: "Spraying", quantity: 2, unit_price: 40 } ])
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "booking a visit shows the job beside the form" do
    get new_admin_job_visit_path(@job)
    assert_select ".form-split form[action=?]", admin_job_visits_path(@job)
    assert_select ".form-split #visit-job-summary", /Maria Lopez.*Spraying\s*× 2.*Side gate.*No visits booked yet/m
  end

  test "recording a payment shows what's left to pay beside the form" do
    invoice = as_business(@business) { Invoice.from_job!(@job, by: @owner).tap { _1.mark_sent!(by: @owner, channel: "link") } }
    get new_admin_invoice_payment_path(invoice)
    assert_select ".form-split #payment-invoice-summary", /Left to pay\s*\$80\.00/
  end

  test "logging a request says what happens next" do
    get new_admin_service_request_path
    assert_select ".form-split #request-next-steps li", 3
  end

  test "the builders save as you go: no Save draft button (except without JavaScript), and Send says what it sends" do
    quote = as_business(@business) { Quote.start(client: @maria).tap(&:save!) }
    get edit_admin_quote_path(quote)
    assert_select "#autosave-note", /Changes save as you go/
    assert_match(/<noscript>.*value="Save draft".*<\/noscript>/m, response.body)
    assert_select "a[href^=?]", new_admin_quote_send_path(quote), /Send quote/

    invoice = as_business(@business) { Invoice.start(client: @maria).tap(&:save!) }
    get edit_admin_invoice_path(invoice)
    assert_select "#autosave-note", /Changes save as you go/
    assert_select "a[href^=?]", new_admin_invoice_send_path(invoice), /Send invoice/
  end
end
