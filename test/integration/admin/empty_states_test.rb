require "test_helper"

# PLT-21: empty pages and cards use the kit's empty state and invite the next step. The sweep in
# design_system_test.rb checks the shape on every page; these cover the states it can't reach.
class Admin::EmptyStatesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "automations" => true, "message_templates" => true } })
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "Automations: the empty state holds New automation until there's one, then the header does" do
    get admin_automations_path
    assert_select ".card .empty", text: /No automations yet.*ready-made one below/m do
      assert_select "a.btn-secondary[href=?]", new_admin_automation_path, text: /New automation/
    end
    assert_select ".card-head a[href=?]", new_admin_automation_path, 0
    assert_select ".empty-title", "Nothing yet" # Recent activity

    post recipe_admin_automations_path(key: AutomationRecipe::ALL.keys.first)
    get admin_automations_path
    assert_select ".card-head a.btn-secondary[href=?]", new_admin_automation_path, 1
    assert_select ".empty-title", { text: "No automations yet", count: 0 }
  end

  test "Messages: the empty state holds New template until there's one" do
    get admin_message_templates_path
    assert_select ".empty", text: /No templates of your own yet/ do
      assert_select "a.btn-secondary[href=?]", new_admin_custom_message_template_path
    end
    assert_select ".card-head a[href=?]", new_admin_custom_message_template_path, 0

    as_business(@business) { MessageTemplate.create!(name: "Check-in", subject: "Hello", body: "Hi") }
    get admin_message_templates_path
    assert_select ".card-head a[href=?]", new_admin_custom_message_template_path, 1
    assert_select ".empty", 0
  end

  test "Home, My day and the data log: an empty card is the kit's empty state, and the tour targets stay" do
    get admin_root_path
    assert_select "#todays-visits .empty .empty-title", "Nothing booked today"
    assert_select "[data-tour=checklist]"

    get admin_my_day_path
    assert_select "[data-tour=today] .empty .empty-title", "Nothing booked for you today"
    assert_select "[data-tour=coming_up] .empty .empty-title", "Nothing coming up"

    get admin_data_exports_path
    assert_select ".empty .empty-title", "Nothing in the log yet"
  end

  test "Schedule: an empty week or day says so on the desktop grid, with no later visit booked (#299)" do
    get admin_schedule_path
    assert_select "#next-visit.md\\:block", text: /Nothing booked this week\./
    assert_select "#next-visit a", 0
    get admin_schedule_path(date: (@business.today + 14).iso8601) # a week without today: the phone agenda's card too
    assert_select "#schedule-agenda .empty-title", "Nothing booked this week"

    get admin_schedule_path(view: "day", date: (@business.today + 1).iso8601)
    assert_select "#next-visit", text: /Nothing booked this day\./
  end
end
