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
    assert_select "#your-day-link", 0
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
    assert_select "nav a[aria-current=page][href=?]", admin_root_path, /Home/

    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    assert_select "nav a[href=?]", admin_my_day_path, /My day/
  end
end
