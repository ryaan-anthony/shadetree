require "test_helper"

# MKT-04: Plausible loads only on marketing pages when configured (never in development or
# test), and the funnel's app steps are sent from the server with no personal data.
class MarketingAnalyticsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def with_analytics(&)
    env = { "ANALYTICS_HOST" => "https://stats.example.com", "ANALYTICS_DOMAIN" => "getshadetree.com" }
    env.each { ENV[_1] = _2 }
    Rails.configuration.x.analytics = true
    yield
  ensure
    env.each_key { ENV.delete(_1) }
    Rails.configuration.x.analytics = false
  end

  def replacing_http_start(implementation)
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start, &implementation)
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  test "off by default: no script and no events" do
    get root_path
    assert_select "script[data-domain]", false
    assert_no_enqueued_jobs(only: AnalyticsEventJob) do
      post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com", password: "long enough phrase", terms_of_service: "1" } }
    end
  end

  test "when configured, the script is on marketing pages only, never the staff app or client pages" do
    with_analytics do
      get pricing_path
      assert_select "script[data-domain='getshadetree.com'][src='https://stats.example.com/js/script.js'][defer]"
      get new_user_registration_path
      assert_select "script[data-domain]", 1
      invitation = as_business(businesses(:one)) { Invitation.create!(email: "new@example.com", role: "technician", invited_by: users(:one)) }
      get invitation_path(invitation.token)
      assert_select "script[data-domain]", false, "no token reaches analytics"
      sign_in users(:one)
      get admin_root_path
      assert_select "script[data-domain]", false
      get edit_user_registration_path
      assert_select "script[data-domain]", false
      business = businesses(:one)
      business.update!(request_form_enabled: true)
      get public_request_path(business.handle)
      assert_select "script[data-domain]", false
    end
  end

  test "sign-up, a new business and the first quote sent are sent as events, with no ids or personal data" do
    with_analytics do
      assert_enqueued_with(job: AnalyticsEventJob, args: [ "Sign-up Completed", "https://getshadetree.com/app/signed-up", "Agent/1", "127.0.0.1" ]) do
        post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com", password: "long enough phrase", terms_of_service: "1" } },
                                     headers: { "User-Agent" => "Agent/1" }
      end
      sign_out :user
      assert_enqueued_with(job: AnalyticsEventJob, args: [ "Business Created", "https://getshadetree.com/app/business-created", "Agent/1", "127.0.0.1" ]) do
        sign_in users(:one)
        post admin_business_path, params: { business: { name: "New Crew", industry: "cleaning" } }, headers: { "User-Agent" => "Agent/1" }
      end
      business = Business.find_by!(name: "New Crew")
      quote = as_business(business) do
        client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
        Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "100", "taxable" => "0" } ]); _1.save! }
      end
      assert_enqueued_with(job: AnalyticsEventJob, args: [ "First Quote Sent", "https://getshadetree.com/app/first-quote-sent", "", "127.0.0.1" ]) do
        post admin_quote_send_path(quote), params: { channel: "email", quote_send: { to: "maria@example.com", subject: "Quote", message: "Hi" } }
      end
      assert_no_enqueued_jobs(only: AnalyticsEventJob) { post admin_quote_send_path(quote), params: { channel: "link" } }
      quote2 = as_business(business) { Quote.start(client: quote.client).tap { _1.sync_line_items([ { "key" => "a", "name" => "More", "quantity" => "1", "unit_price" => "5", "taxable" => "0" } ]); _1.save! } }
      assert_no_enqueued_jobs(only: AnalyticsEventJob) { post admin_quote_send_path(quote2), params: { channel: "link" } }
    end
  end

  test "a failed sign-up sends nothing, and a bare host leaves analytics off" do
    with_analytics do
      assert_no_enqueued_jobs(only: AnalyticsEventJob) do
        post user_registration_path, params: { user: { first_name: "", email: "bad", password: "x", terms_of_service: "1" } }
      end
      ENV["ANALYTICS_HOST"] = "stats.example.com"
      assert_not Analytics.enabled?
    end
  end

  test "the job posts the event to Plausible and never fails the app" do
    with_analytics do
      sent = nil
      fake = Object.new.tap { |o| o.define_singleton_method(:request) { |r| sent = r } }
      fake.define_singleton_method(:request) { |r| sent = r; Net::HTTPOK.new("1.1", "202", "Accepted") }
      replacing_http_start(->(*, **, &block) { block.call(fake) }) do
        AnalyticsEventJob.perform_now("Sign-up Completed", "https://getshadetree.com/app/signed-up", "Agent/1", "203.0.113.4")
      end
      assert_equal "/api/event", sent.path
      assert_equal({ "name" => "Sign-up Completed", "url" => "https://getshadetree.com/app/signed-up", "domain" => "getshadetree.com" }, JSON.parse(sent.body))
      assert_equal "203.0.113.4", sent["X-Forwarded-For"]
      replacing_http_start(->(*, **) { raise Errno::ECONNREFUSED }) do
        assert_nothing_raised { AnalyticsEventJob.perform_now("Sign-up Completed", "u", "a", "1.2.3.4") }
      end
    end
  end
end
