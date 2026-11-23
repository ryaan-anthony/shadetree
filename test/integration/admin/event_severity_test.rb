require "test_helper"

# PLT-17: one severity per event. An undelivered email, a failed payment and a failed
# automation step look equally serious (danger icon, colour and words) wherever they show;
# other event icons are neutral. Role labels on Team are plain.
class Admin::EventSeverityTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @maria = as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
    @quote = as_business(@business) do
      Quote.start(client: @maria).tap do |quote|
        quote.title = "Gutter guards"
        quote.sync_line_items([ { "key" => "a", "name" => "Guards", "quantity" => "1", "unit_price" => "240", "taxable" => "0" } ])
        quote.save!
        email = EmailMessage.create!(kind: "quote_sent", to: "maria@example.com", related: quote)
        quote.mark_sent!(by: @owner, channel: "email", recipient: email.to, email_message: email)
        email.mark!("bounced", error: "550 5.1.1")
      end
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "an undelivered email is danger on the record's page, in the list, on the client page and its timeline, and in Notifications" do
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem.banner-danger h2", "Email not delivered"
    assert_select ".text-danger", /Address refused/ # the send history

    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger[data-status='email:not_delivered']", "Email not delivered"

    get admin_client_path(@maria)
    assert_select "[id^=email-] svg.text-danger"
    assert_select "[id^=email-] .text-danger", "Address refused"
    assert_select "#client-timeline li svg.text-danger", 1
    assert_select "#client-timeline .badge-danger", "Email not delivered"
    assert_select "#client-timeline svg.text-warning, [id^=email-] svg.text-warning", 0
    assert_select "#client-timeline li svg:not(.text-danger)" do |icons|
      icons.each { assert_includes _1["class"], "text-faint", "other event icons are neutral" }
    end

    get admin_notifications_path
    assert_select "#notifications li", /wasn't delivered/ do |rows|
      assert_select rows.first, "svg.text-danger"
    end
  end

  test "a failed automation step says so in danger on the record's page" do
    as_business(@business) do
      run = AutomationRun.create!(rule_name: "Tell the office", trigger: "quote_sent", subject: @quote, run_at: 1.hour.ago, status: "failed")
      run.note!("notify_team", "failed", "Nobody to tell.")
      run.save!
    end
    get admin_quote_path(@quote)
    assert_select "#automation-runs .badge-danger", "Didn't finish"
    assert_select "#automation-runs .text-danger", /Failed: Nobody to tell\./
  end

  test "a failed payment for the plan is danger" do
    @business.update!(plan: plans(:starter), billing_status: "past_due")
    get admin_root_path
    assert_select "#billing-banner.banner-danger", /payment for your plan failed|wasn't paid/
  end

  test "role labels on Team are plain, the Owner's included" do
    get admin_team_path
    assert_select "td .badge", minimum: 1
    assert_select "td .badge:not(.badge-plain)", 0
    assert_select ".badge-dark", 0
  end
end
