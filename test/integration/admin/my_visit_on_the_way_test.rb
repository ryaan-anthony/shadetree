require "test_helper"

# JOB-12: "On my way" from My day and the visit's page: who sees it, the sheet, warnings, the
# limits, no email, unconfirmed senders, support viewing as a member, roles and tenancy.
class Admin::MyVisitOnTheWayTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", client_visit_emails: { "on_my_way" => "1" }, plan_overrides: { "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @tech = member_with_role(:technician).tap { _1.update!(first_name: "Marcus") }
    travel_to ActiveSupport::TimeZone["America/New_York"].parse("2026-12-10 10:45")
    as_business(@business) do
      @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" }, { kind: "phone", value: "(555) 010-0100" } ])
      @job = Job.create!(client: @client, title: "Spring cleanup")
      @visit = book(Date.new(2026, 12, 10))
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  teardown { travel_back }

  def book(on, crew: [ @tech.id ]) = @job.visits.new(scheduled_on: on, timing: "window", start_time: "09:00", window_end_time: "12:00", assignee_ids: crew).tap { _1.schedule!(by: @owner, notify_client: false) }
  def on_the_way = admin_my_visit_on_the_way_path(@visit)

  test "someone going sees On my way on My day and the visit's page; sending names the time and changes the row" do
    get admin_my_day_path
    assert_select "#my-visit-#{@visit.uid} a[href=?]", new_admin_my_visit_on_the_way_path(@visit, from: "day"), /On my way/
    assert_select "#my-visit-#{@visit.uid} dialog[aria-labelledby] h2", "On my way to Maria Lopez"
    frame = "on-the-way-sheet-#{@visit.uid}-day"
    assert_select "#my-visit-#{@visit.uid} dialog turbo-frame##{frame}[loading=lazy][target=_top][src=?]", new_admin_my_visit_on_the_way_path(@visit, from: "day")
    get new_admin_my_visit_on_the_way_path(@visit, from: "day"), headers: { "Turbo-Frame" => frame }
    assert_select "turbo-frame##{frame} form[action=?] button", on_the_way, /30 min\s*about 11:15 am/
    assert_select "input[type=time][name=at][min='10:50'][step='300']", 1, "the earliest pick, on a 5-minute mark"
    get admin_my_visit_path(@visit)
    assert_select "#visit-action a[href=?]", new_admin_my_visit_on_the_way_path(@visit, from: "visit"), /On my way/
    assert_select "#visit-action form[action=?]", start_admin_my_visit_path(@visit), 1, "Start stays separate"

    post on_the_way, params: { minutes: 30, from: "day" }
    assert_redirected_to admin_my_day_path
    assert_match "arriving about 11:15 am", flash[:notice]
    assert_equal "scheduled", @visit.reload.status, "sending doesn't start the visit"
    follow_redirect!
    assert_select "#my-visit-#{@visit.uid}", /On the way · about 11:15 am/
    assert_select "#my-visit-#{@visit.uid} a", /Change time/
  end

  test "a time with a warning shows it and the choice, and is sent once it's been seen" do
    travel_to ActiveSupport::TimeZone["America/New_York"].parse("2026-12-10 11:45")
    get new_admin_my_visit_on_the_way_path(@visit, from: "day")
    assert_select "p[id$='-30-warning']", "That's after the 9 am–12 pm window."
    post on_the_way, params: { minutes: 30 }
    assert_response :unprocessable_content
    assert_select ".banner-warning[data-controller=announce]", /About 12:15 pm\. That's after the 9 am–12 pm window\. You can still send it\./
    assert_nil @visit.reload.on_the_way_arrives_at
    post on_the_way, params: { minutes: 30, seen_warning: @visit.on_the_way_arrival(minutes: 30).iso8601 }
    assert_redirected_to admin_my_visit_path(@visit)
    assert @visit.reload.on_the_way?
  end

  test "a picked time that warns rounds up and is sent with Send anyway" do
    post on_the_way, params: { at: "12:07" } # 12:10, after the window
    assert_response :unprocessable_content
    assert_select ".banner-warning[data-controller=announce]", /About 12:10 pm\. That's after the 9 am–12 pm window\./
    anyway = css_select("form").find { _1.text.include?("Send anyway") }
    assert_equal "2026-12-10T17:10:00Z", anyway.at_css("input[name=arrives_at]")["value"], "an unambiguous UTC time"
    travel 30.seconds
    post on_the_way, params: anyway.css("input[type=hidden]").to_h { [ _1["name"], _1["value"] ] }.except("authenticity_token")
    assert_redirected_to admin_my_visit_path(@visit)
    assert_equal "12:10 pm", @visit.reload.on_the_way_time_label
  end

  test "My day's queries don't grow with the visits on it" do
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_my_day_path }
      queries
    end
    one = count.()
    as_business(@business) do
      3.times { book(Date.new(2026, 12, 10)) }
      Client.create!(display_name: "Ben", contact_methods_attributes: [ { kind: "email", value: "ben@example.com" } ]).then do |ben|
        Job.create!(client: ben, title: "Hedges").visits.new(scheduled_on: Date.new(2026, 12, 10), assignee_ids: [ @tech.id ]).tap { _1.schedule!(by: @owner, notify_client: false) }
      end
    end
    many = count.()
    assert_operator many, :<=, one + 2, "4 more visits for today, with their sheets, cost no queries each"
  end

  test "a picked time, a refused one, and the limits say why" do
    post on_the_way, params: { at: "10:45" }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /at least 5 minutes from now/
    post on_the_way, params: { at: "11:30" }
    assert_equal "11:30 am", @visit.reload.on_the_way_time_label
    post on_the_way, params: { minutes: 15 }
    assert_select "[role=alert]", /less than a minute ago/
    get new_admin_my_visit_on_the_way_path(@visit)
    assert_select ".banner-info", /less than a minute ago/
    assert_select "button", { text: /15 min/, count: 0 }
  end

  test "no usable email: the sheet says so, the time is kept, and the row offers call and text with the message filled in" do
    as_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    get new_admin_my_visit_on_the_way_path(@visit)
    assert_select ".banner-warning", /no email address we can use, so nothing is emailed/
    post on_the_way, params: { minutes: 30 }
    assert_match "no email address we can use", flash[:notice]
    follow_redirect!
    body = ERB::Util.url_encode("Hi, it's Marcus from #{@business.name}. I'm on the way, arriving about 11:15 am.")
    assert_select "main a[href=?]", "sms:5550100100?&body=#{body}", /Text/
    assert_select "main a[href='tel:5550100100']", 1, "once on the visit's page"
    get admin_my_day_path
    assert_select "#my-visit-#{@visit.uid} a[href='tel:5550100100']", /Call/
    assert_select "#my-visit-#{@visit.uid} a[href=?]", "sms:5550100100?&body=#{body}", /Text/
  end

  test "off, not today, started, or an erased client: no button, and a send is refused" do
    @business.update!(client_visit_emails: { "on_my_way" => "0" })
    get admin_my_day_path
    assert_select "a", { text: /On my way/, count: 0 }
    post on_the_way, params: { minutes: 30 }
    assert_redirected_to admin_my_visit_path(@visit)
    assert_nil @visit.reload.on_the_way_arrives_at
    @business.update!(client_visit_emails: { "on_my_way" => "1" })
    tomorrow = as_business(@business) { book(Date.new(2026, 12, 11)) }
    post admin_my_visit_on_the_way_path(tomorrow), params: { minutes: 30 }
    assert_nil tomorrow.reload.on_the_way_arrives_at
    as_business(@business) { @client.update_columns(erased_at: Time.current) }
    get admin_my_visit_path(@visit)
    assert_select "a", { text: /On my way/, count: 0 }
  end

  test "people not going (office staff and the owner included) and other businesses can't send" do
    [ @owner, member_with_role(:admin) ].each do |user|
      sign_in user
      post switch_admin_business_path, params: { business: @business.uid }
      post on_the_way, params: { minutes: 30 }
      assert_response :not_found
      get new_admin_my_visit_on_the_way_path(@visit)
      assert_response :not_found
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "email", value: "theirs@example.com" } ])
      Job.create!(client:, title: "Theirs").visits.new(scheduled_on: Date.new(2026, 12, 10)).tap { _1.schedule!(by: nil) }
    end
    assert_not_found_across_businesses { post admin_my_visit_on_the_way_path(theirs), params: { minutes: 30 } }
    assert_nil @visit.reload.on_the_way_arrives_at
  end

  test "an unconfirmed sender can't send" do
    @tech.update_columns(confirmed_at: nil)
    post on_the_way, params: { minutes: 30 }
    assert_match "Confirm your email address", flash[:alert]
    assert_nil @visit.reload.on_the_way_arrives_at
  end

  test "support viewing as a member can open the sheet but not send, in either mode" do
    business = businesses(:two)
    business.update!(timezone: "America/New_York", client_visit_emails: { "on_my_way" => "1" })
    visit = as_business(business) do
      client = Client.create!(display_name: "Ana", contact_methods_attributes: [ { kind: "email", value: "ana@example.com" } ])
      Job.create!(client:, title: "Hedges").visits.new(scheduled_on: Date.new(2026, 12, 10), assignee_ids: [ users(:two).id ]).tap { _1.schedule!(by: nil) }
    end
    sign_in_operator
    post ops_business_impersonation_path(business), params: { member: business_users(:two).uid, reason: "Ticket: on my way" }
    get new_admin_my_visit_on_the_way_path(visit)
    assert_response :success
    post admin_my_visit_on_the_way_path(visit), params: { minutes: 30 }
    assert_match "read-only", flash[:alert]
    patch ops_impersonation_path, params: { mode: "write", reason: "Checking the sheet" }
    post admin_my_visit_on_the_way_path(visit), params: { minutes: 30 }
    assert_match "can't change this", flash[:alert]
    assert_nil visit.reload.on_the_way_arrives_at
  end
end
