require "test_helper"

# CAT-06: the Hours settings tab: weekly hours and closures.
class Admin::HoursTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def closure(business: @business, **attrs) = as_business(business) { Closure.create!(reason: "Thanksgiving", starts_on: Date.new(2026, 11, 26), **attrs) }

  test "only owners and admins manage hours and closures" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_hours_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch admin_hours_path, params: { preset: "weekdays" } }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_closures_path, params: { closure: { reason: "Off", starts_on: "2026-12-01" } } }
  end

  test "another business's closures aren't found" do
    theirs = closure(business: businesses(:two))
    assert_not_found_across_businesses { get edit_admin_closure_path(theirs) }
    assert_not_found_across_businesses { patch admin_closure_path(theirs), params: { closure: { reason: "Mine" } } }
    assert_not_found_across_businesses { delete admin_closure_path(theirs) }
    assert as_business(businesses(:two)) { Closure.exists?(theirs.id) }
  end

  test "hours start unset, then are saved per day" do
    get admin_hours_path
    assert_select "nav.tabs a[aria-current=page]", "Hours"
    assert_select ".banner", /hours aren't set yet/
    assert_select "input[name='hours[1][open]']:not([checked])"

    patch admin_hours_path, params: { hours: { "1" => { open: "1", opens: "07:30", closes: "16:00" }, "2" => { opens: "08:00", closes: "17:00" } } }
    assert_redirected_to admin_hours_path
    assert_equal({ "1" => { "opens" => "07:30", "closes" => "16:00" } }, @business.reload.weekly_hours)
    follow_redirect!
    assert_select ".banner", { text: /aren't set yet/, count: 0 }
    assert_select "input[name='hours[1][open]'][checked]"
    assert_select "input[name='hours[1][opens]'][value='07:30']"
    assert_select "input[name='hours[2][open]']:not([checked])"
  end

  test "invalid hours are shown and not saved" do
    patch admin_hours_path, params: { hours: { "3" => { open: "1", opens: "18:00", closes: "09:00" } } }
    assert_response :unprocessable_content
    assert_select ".banner-danger li", "Wednesday closes before it opens. Hours that run past midnight aren't supported."
    assert_select "input[name='hours[3][opens]'][value='18:00']", 1, "what they typed is kept"
    assert_nil @business.reload.weekly_hours

    patch admin_hours_path, params: { hours: { "2" => { open: "1", opens: "", closes: "17:00" } } }
    assert_select ".banner-danger li", "Tuesday needs an opening time."
    assert_select "input[name='hours[2][open]'][checked]", 1, "the day stays open, so its fields show"
    assert_select "input[name='hours[2][opens]'][aria-invalid=true]:not([value='08:00'])", 1, "what they cleared stays cleared"
    assert_select "input[name='hours[1][opens]']:not([aria-invalid])"
  end

  test "only the weekdays preset exists" do
    patch admin_hours_path, params: { preset: "everyday" }
    assert_redirected_to admin_hours_path
    assert_nil @business.reload.weekly_hours
  end

  test "the weekdays preset" do
    patch admin_hours_path, params: { preset: "weekdays" }
    assert_equal WeeklyHours::WEEKDAYS_8_TO_5, @business.reload.weekly_hours
    assert_equal "Hours set to weekdays, 8 am to 5 pm.", flash[:notice]
    get admin_hours_path
    assert_select "form[data-turbo-confirm*='Replace your hours']", 1, "replacing saved hours asks first"
  end

  test "adding, editing and removing closures" do
    post admin_closures_path, params: { closure: { reason: "Christmas Eve", starts_on: "2026-12-24", part_of_day: "1", start_time: "12:00", end_time: "17:00" } }
    assert_redirected_to admin_hours_path
    eve = as_business(@business) { Closure.find_by!(reason: "Christmas Eve") }
    assert_equal [ Date.new(2026, 12, 24), 720, 1020 ], [ eve.ends_on, eve.start_minute, eve.end_minute ]

    travel_to Time.utc(2026, 11, 17, 15) do
      get admin_hours_path
      assert_select "#closure-#{eve.uid}", /Christmas Eve.*Thu, Dec 24, 12 pm–5 pm/m
      assert_select "li[role=group]", 0, "list items keep their role"
    end

    patch admin_closure_path(eve), params: { closure: { reason: "Christmas", starts_on: "2026-12-25", ends_on: "", part_of_day: "0", repeats_yearly: "1" } }
    assert_redirected_to admin_hours_path
    eve.reload
    assert_equal [ "Christmas", Date.new(2026, 12, 25), nil, true ], [ eve.reason, eve.ends_on, eve.start_minute, eve.repeats_yearly ]

    post admin_closures_path, params: { closure: { reason: "", starts_on: "2026-12-05", ends_on: "2026-12-01" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Last day is before the first day/

    delete admin_closure_path(eve)
    assert_redirected_to admin_hours_path
    assert_not as_business(@business) { Closure.exists?(eve.id) }
  end

  test "past closures are listed apart from upcoming and yearly ones" do
    old = closure(reason: "Last spring", starts_on: Date.new(2026, 4, 1))
    yearly = closure(reason: "New Year", starts_on: Date.new(2026, 1, 1), repeats_yearly: true)
    travel_to Time.utc(2026, 11, 17, 15) do
      get admin_hours_path
    end
    assert_select "details #closure-#{old.uid}"
    assert_select "details #closure-#{yearly.uid}", 0
    assert_select "#closure-#{yearly.uid}", /New Year.*Every year/m
  end
end
