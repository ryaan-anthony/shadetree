require "test_helper"

# #289: Home is the one place to start: the checklist, then today (your own visits if you go on
# them, the team's otherwise), then money owed and what needs you. My day is the phone-first
# day view, reached from Home; only people who just do field work land on it.
class Admin::HomeTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", onboarded_at: Time.current)
    @owner = users(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "2155551212" } ])
      @job = Job.create!(client: @maria, title: "Ants")
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def book(user = nil)
    as_business(@business) do
      @job.visits.create!(scheduled_on: @business.today, timing: "anytime", duration_minutes: 60).tap do |visit|
        visit.assignments.create!(business: @business, user:) if user
      end
    end
  end

  test "an owner who goes on visits sees their own day, with Your day one tap away" do
    tech = member_with_role(:technician)
    book(@owner)
    book(tech)
    get admin_root_path
    assert_select "#todays-visits h2", "Your visits today"
    assert_select "#todays-visits", /1 visit/
    assert_select "#todays-visits a#your-day-link[href=?]", admin_my_day_path, /Your day/
    assert_select "#todays-visits a[href=?]", admin_schedule_path, /The team has 1 other visit today/
  end

  test "an owner who doesn't go on visits sees the team's day, by person" do
    tech = member_with_role(:technician)
    book(tech)
    get admin_root_path
    assert_select "#todays-visits h2", "Today's visits"
    assert_select "#todays-visits section h3", tech.full_name
    assert_select "#todays-visits #your-day-link[href=?]", admin_my_day_path # still one tap to their own day
  end

  test "money owed, and how much of it is late, comes after today" do
    as_business(@business) do
      invoice = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "120" } ]); _1.update!(tax_rates: []) }
      invoice.mark_sent!(by: @owner, channel: "link")
      invoice.update_columns(issued_on: @business.today - 10, due_on: @business.today - 1)
    end
    get admin_root_path
    assert_select "#money-owed", /Clients owe you\s*\$120\.00\s*\$120\.00 of it is overdue/
    assert_select "#money-owed a[href=?]", admin_invoices_path(filter: "overdue")
    order = css_select("#todays-visits, #money-owed").map { _1["id"] }
    assert_equal %w[todays-visits money-owed], order
  end

  test "office members reach My day from Home; technicians keep it in the menu" do
    get admin_root_path
    assert_select "nav a[href=?]", admin_my_day_path, 0
    get admin_my_day_path
    assert_response :success
    assert_select "nav a[aria-current=true][href=?]", admin_root_path, /Home/ # the section, not the page

    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    assert_select "nav a[href=?]", admin_my_day_path, /My day/
  end

  test "an overpaid invoice doesn't hide what's owed on another" do
    as_business(@business) do
      owed = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "120" } ]); _1.update!(tax_rates: []) }
      owed.mark_sent!(by: @owner, channel: "link")
      over = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "50" } ]); _1.update!(tax_rates: []) }
      over.mark_sent!(by: @owner, channel: "link")
      over.update_columns(amount_paid_cents: 9_000) # paid $90 on a $50 invoice
    end
    get admin_root_path
    assert_select "#money-owed", /Clients owe you\s*\$120\.00/
  end

  test "an owner with no visits today, and none open from earlier, sees the team's day; with an old open one, their own" do
    tech = member_with_role(:technician)
    book(tech)
    as_business(@business) do
      @job.visits.create!(scheduled_on: @business.today - 30, timing: "anytime", duration_minutes: 60, status: "completed")
        .assignments.create!(business: @business, user: @owner)
    end
    get admin_root_path
    assert_select "#todays-visits h2", "Today's visits", "a visit long ago, done, doesn't make it their day"
    assert_select "#your-day-link[href=?]", admin_my_day_path
    as_business(@business) do
      @job.visits.create!(scheduled_on: @business.today - 2, timing: "anytime", duration_minutes: 60).assignments.create!(business: @business, user: @owner)
    end
    get admin_root_path
    assert_select "#todays-visits h2", "Your visits today"
    assert_select "#earlier-open a[href=?]", admin_my_day_path, text: "1 visit still open from earlier"
  end

  test "a custom role with field work and settings, without office work, has one current link on My day" do
    role = as_business(@business) { Role.create!(name: "Lead", permissions: %w[field_work business_settings]) }
    member = member_with_role(:technician)
    as_business(@business) { @business.business_users.find_by!(user: member).update!(role: "custom", role_id: role.id) }
    sign_in member
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    assert_select "nav[aria-label=Primary] a[aria-current]", 1
    assert_select "nav[aria-label=Primary] a[aria-current=page][href=?]", admin_my_day_path
  end

  test "the team's day doesn't query per visit" do
    techs = 3.times.map { member_with_role(:technician) }
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_root_path }
      queries
    end
    book(techs[0])
    one = count.call
    techs.each { book(_1) }
    assert_equal one, count.call, "more visits and people, the same queries"
  end

  test "a follow-up's page (My requests) counts as My day: current for a technician, Home's section for the office" do
    tech = member_with_role(:technician)
    request = as_business(@business) do
      ServiceRequest.create!(client: @maria, source: "phone", description: "Ants").tap do |r|
        RequestFollowUp.assign!(r, { user: tech, scheduled_on: @business.today }, by: @owner)
      end
    end
    other = as_business(@business) do
      ServiceRequest.create!(client: @maria, source: "phone", description: "Wasps").tap do |r|
        RequestFollowUp.assign!(r, { user: @owner, kind: "call", scheduled_on: @business.today }, by: @owner)
      end
    end
    get admin_my_request_path(other)
    assert_select "nav[aria-label=Primary] a[aria-current=true][href=?]", admin_root_path

    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_request_path(request)
    assert_select "nav[aria-label=Primary] a[aria-current=page][href=?]", admin_my_day_path
  end

  def follow_up(name, user: @owner, **when_)
    as_business(@business) do
      client = Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: format("51255501%02d", @phones = @phones.to_i + 1) } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence for #{name}", **when_.extract!(:location))
                    .tap { RequestFollowUp.assign!(_1, { user:, scheduled_on: @business.today, **when_ }, by: @owner) }
    end
  end

  test "JOB-06: request follow-ups count as your day: listed as My day labels them, not Nothing booked" do
    tech = member_with_role(:technician)
    book(tech)
    request = follow_up("Sam Ortiz", timing: "exact", start_time: "14:00")
    call = follow_up("Ana Diaz", kind: "call")
    get admin_root_path
    assert_select "#todays-visits h2", "Your visits today", "an office manager whose only work today is follow-ups"
    assert_select "#todays-visits", /2 request follow-ups · times in/
    assert_select "#todays-visits", { text: /Nothing booked/, count: 0 }
    assert_select "#todays-visits li", /Site visit for a request.*Sam Ortiz.*2 pm/m
    assert_select "#todays-visits li", /Call for a request.*Ana Diaz.*Anytime/m
    assert_select "#todays-visits a[href=?]", admin_my_request_path(request), "Sam Ortiz"
    assert_select "#todays-visits a[href=?]", admin_my_request_path(call), "Ana Diaz"

    book(@owner)
    get admin_root_path
    assert_select "#todays-visits", /1 visit and 2 request follow-ups/
  end

  test "JOB-06: an overdue follow-up, or a done one not yet quoted, is still open from earlier" do
    old = follow_up("Lee Park", scheduled_on: @business.today - 3)
    get admin_root_path
    assert_select "#todays-visits h2", "Your visits today"
    assert_select "#todays-visits", /Nothing today · times in/
    assert_select "#earlier-open a[href=?]", admin_my_day_path, text: "1 request follow-up still open from earlier"

    as_business(@business) { old.follow_up.update!(done_at: Time.current, done_by: @owner) }
    as_business(@business) { @job.visits.create!(scheduled_on: @business.today - 2, timing: "anytime", duration_minutes: 60).assignments.create!(business: @business, user: @owner) }
    get admin_root_path
    assert_select "#earlier-open a", text: "1 visit and 1 request follow-up still open from earlier"
  end

  test "JOB-06: a follow-up at a location in another zone is placed on that location's day" do
    travel_to Time.utc(2026, 11, 23, 5, 30) # 00:30 Monday in New York; 7:30 pm Sunday in Honolulu
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    honolulu = as_business(@business) { Location.create!(name: "Island yard", timezone: "Pacific/Honolulu") }
    follow_up("Kai Akana", location: honolulu, scheduled_on: Date.new(2026, 11, 22), timing: "exact", start_time: "20:00")
    get admin_root_path
    assert_select "#todays-visits li", /Kai Akana.*8 pm HST/m
    assert_select "#todays-visits", /1 request follow-up · times in/, "still Sunday there, so today, not from earlier"
    assert_select "#earlier-open", 0
  end

  test "JOB-06: follow-ups on Home follow its location filter, as visits do (owner, 2026-11-22)" do
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    north = as_business(@business) { Location.create!(name: "North yard") }
    main = @business.primary_location
    follow_up("Sam Ortiz", location: north)
    follow_up("Ana Diaz", location: main, kind: "call")
    as_business(@business) { @job.update!(location: north) }
    book(@owner)
    get admin_root_path(location: "all")
    assert_select "#todays-visits", /1 visit and 2 request follow-ups/
    get admin_root_path(location: main.uid)
    assert_select "#todays-visits", /1 request follow-up · times in/
    assert_select "#todays-visits li", /Ana Diaz/
    assert_select "#todays-visits li", { text: /Sam Ortiz/, count: 0 }
    get admin_root_path(location: north.uid)
    assert_select "#todays-visits", /1 visit and 1 request follow-up/
    assert_select "#todays-visits li", { text: /Ana Diaz/, count: 0 }
  end

  test "JOB-06: an office-only role (no My day) sees its follow-ups on Home, each opening its own page" do
    role = as_business(@business) { Role.create!(name: "Office", permissions: %w[office]) }
    clerk = member_with_role(:admin)
    as_business(@business) { @business.business_users.find_by!(user: clerk).update!(role: "custom", role_id: role.id) }
    today = follow_up("Sam Ortiz", user: clerk, kind: "call")
    old = follow_up("Lee Park", user: clerk, scheduled_on: @business.today - 2)
    sign_in clerk
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_select "#todays-visits h2", "Your visits today"
    assert_select "#todays-visits", /1 request follow-up · times in/
    assert_select "#todays-visits a[href=?]", admin_my_request_path(today), "Sam Ortiz"
    assert_select "#earlier-open", "1 request follow-up still open from earlier"
    assert_select "#todays-visits a[href=?]", admin_my_request_path(old), "Lee Park"
    assert_select "#todays-visits a[href=?]", admin_my_day_path, 0, "no My day for this role"
    get admin_my_request_path(old)
    assert_response :success
  end

  test "your own day on Home doesn't query per visit or follow-up" do
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_root_path }
      queries
    end
    book(@owner)
    follow_up("Sam Ortiz")
    follow_up("Lee Park", scheduled_on: @business.today - 3)
    one = count.call
    2.times { book(@owner) }
    follow_up("Ana Diaz", kind: "call")
    follow_up("Kim Chu", scheduled_on: @business.today - 1)
    # A rewritten row moves in the table, so an unordered query returns it last (CI saw 41 for 40
    # when the table's order happened to differ from the visits' order).
    as_business(@business) { Visit.order(:id).first.update_column(:updated_at, Time.current) }
    assert_equal one, count.call, "more visits and follow-ups, the same queries"
  end
end
