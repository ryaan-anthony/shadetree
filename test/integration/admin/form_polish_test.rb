require "test_helper"

# #289 (admin UX review), visual polish: long forms have what they're about beside them (first,
# for phones and screen readers), the builders save one way (as you go), and a flow's buttons
# keep their words.
class Admin::FormPolishTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(country: "US")
    @owner = users(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "2155551212" } ])
      @job = Job.create!(client: @maria, title: "Ants", instructions: "Side gate",
                         line_items_attributes: 8.times.map { { name: "Item #{_1}", quantity: 2, unit_price: 10 } })
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def order = css_select(".form-split > *").map { _1.name }

  test "booking or changing a visit shows the job first, then the form" do
    get new_admin_job_visit_path(@job)
    assert_equal %w[aside form], order
    assert_select "aside[aria-labelledby=visit-job-summary-h] #visit-job-summary", /Maria Lopez.*\(215\) 555-1212.*Item 0\s*2 × \$[\d.,]+.*and 2 more.*Side gate.*No visits booked yet/m
    assert_select "#visit-job-summary li", 7 # six items, then "and 2 more"

    visit = as_business(@business) { @job.visits.create!(scheduled_on: @business.today + 1, timing: "anytime", duration_minutes: 60) }
    as_business(@business) { @job.visits.create!(scheduled_on: @business.today + 2, timing: "anytime", duration_minutes: 60, status: "completed") }
    get edit_admin_job_visit_path(@job, visit)
    assert_equal %w[aside form], order
    assert_select "#visit-job-summary", /No other visits booked\./ # not this one, nor a finished one
  end

  test "recording a payment shows what's owed first: total, paid so far, left to pay, due" do
    invoice = as_business(@business) { Invoice.from_job!(@job, by: @owner).tap { _1.mark_sent!(by: @owner, channel: "link") } }
    as_business(@business) { invoice.record_payment!(by: @owner, amount: "50", received_on: @business.today, payment_method: "cash") }
    get new_admin_invoice_payment_path(invoice)
    assert_equal %w[aside form], order
    assert_select "aside[aria-labelledby=payment-summary-h] #payment-invoice-summary", /What's owed.*Total\s*\$160\.00.*Paid so far\s*\$50\.00.*Left to pay\s*\$110\.00.*Due/m
    assert_select "h2", { text: /Invoice #{invoice.number}/, count: 0 } # the number is the form card's subtitle, not a second heading
  end

  test "a payment on a draft invoice (paid on the spot) shows what's owed without 'Paid so far'" do
    invoice = as_business(@business) { Invoice.from_job!(@job, by: @owner) }
    get new_admin_invoice_payment_path(invoice)
    assert_select "#payment-invoice-summary", /Left to pay\s*\$160\.00/
    assert_select "#payment-invoice-summary", { text: /Paid so far/, count: 0 }
  end

  test "logging a request says what happens next, after the form" do
    get new_admin_service_request_path
    assert_equal %w[form aside], order
    assert_select "#request-next-steps li", 3
  end

  test "the builders save as you go; Save draft is there only for when autosave isn't running" do
    quote = as_business(@business) { Quote.start(client: @maria).tap(&:save!) }
    get edit_admin_quote_path(quote)
    assert_select "#autosave-note", /Changes save as you go: Saved/
    assert_select "#autosave-note [data-quote-builder-target=status][aria-hidden=true]"
    assert_select "input[type=submit][value='Save draft'][data-quote-builder-target=fallback]"
    assert_select "a[href^=?]", new_admin_quote_send_path(quote), /Send quote/

    invoice = as_business(@business) { Invoice.start(client: @maria).tap(&:save!) }
    get edit_admin_invoice_path(invoice)
    assert_select "#autosave-note", /Changes save as you go/
    assert_select "input[type=submit][value='Save draft'][data-quote-builder-target=fallback]"
    assert_select "a[href^=?]", new_admin_invoice_send_path(invoice), /Send invoice/
  end
end
