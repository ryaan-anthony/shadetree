require "test_helper"

# NTF-04 part 2: Settings → Automations: recipes, building and editing rules, switching them on
# and off, the activity list, runs on each record, the plan gate, permissions and tenancy.
class Admin::AutomationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "automations" => true, "message_templates" => true }, "limits" => { "active_automations" => 3 } })
    @template = as_business(@business) { MessageTemplate.create!(name: "Check-in", subject: "About {{document_number}}", body: "Hi {{client_first_name}}") }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def rule_params(**overrides)
    { name: "Chase quotes", trigger: "quote_sent", delay_amount: "2", delay_unit: "days",
      conditions: { still_open: "1", total_at_least: "", client_tag: "" },
      actions: { send_template: { on: "1", template: @template.uid }, notify_team: { on: "1", team: "schedule" }, tag_client: { tag: "ignored" } } }.merge(overrides)
  end

  def rules = as_business(@business) { AutomationRule.order(:id).to_a }

  test "a ready-made automation turns on in one step, bringing its template; pressing again goes to it" do
    get admin_automations_path
    assert_select "#recipe-quote_follow_up button", "Turn on"
    assert_difference -> { as_business(@business) { MessageTemplate.custom.count } } do
      post recipe_admin_automations_path(key: "quote_follow_up")
    end
    rule = rules.last
    assert_redirected_to admin_automations_path
    assert_equal [ "quote_sent", 3 * 24 * 60, "quote_follow_up" ], [ rule.trigger, rule.delay_minutes, rule.recipe ]
    follow_redirect!
    assert_select "#automation-#{rule.uid}", /3 days after a quote is sent, if it's still open: email “Quote follow-up”\./
    assert_select "#recipe-quote_follow_up", /Added/
    post recipe_admin_automations_path(key: "quote_follow_up")
    assert_redirected_to edit_admin_automation_path(rule)
    assert_equal 1, rules.size
    post recipe_admin_automations_path(key: "nope")
    assert_response :not_found
  end

  test "build an automation from the form, edit it, switch it off and on, and delete it" do
    get new_admin_automation_path
    assert_select "select[name='automation_rule[trigger]'] option[data-subject=Quote]"
    post admin_automations_path, params: { automation_rule: rule_params }
    assert_redirected_to admin_automations_path
    rule = rules.last
    assert_equal 2 * 24 * 60, rule.delay_minutes
    assert_equal({ "still_open" => "1" }, rule.conditions, "empty fields aren't conditions")
    assert_equal [ { "type" => "send_template", "template" => @template.uid }, { "type" => "notify_team", "team" => "schedule" } ], rule.actions,
                 "only ticked steps are kept"

    get edit_admin_automation_path(rule)
    assert_select "input[name='automation_rule[delay_amount]'][value='2']"
    assert_select "select[name='automation_rule[delay_unit]'] option[selected]", "days"
    patch admin_automation_path(rule), params: { automation_rule: rule_params(delay_amount: "6", delay_unit: "hours", conditions: { total_at_least: "500" }) }
    assert_equal [ 360, { "total_at_least" => "500" } ], [ rule.reload.delay_minutes, rule.conditions ]

    patch toggle_admin_automation_path(rule)
    assert_not rule.reload.enabled?
    patch toggle_admin_automation_path(rule)
    assert rule.reload.enabled?
    delete admin_automation_path(rule)
    assert_empty rules
  end

  test "steps and conditions that don't fit the trigger are refused, with the reason" do
    post admin_automations_path, params: { automation_rule: rule_params(actions: { invoice_job: { on: "1" } }) }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /doesn't fit/
    post admin_automations_path, params: { automation_rule: rule_params(trigger: "request_received", conditions: { paid_in_full: "1" }) }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /paid in full.*doesn't fit/
    post admin_automations_path, params: { automation_rule: rule_params(actions: {}) }
    assert_select "[role=alert]", /need at least one/
  end

  test "unconfirmed senders can't set up automations; odd values and a deleted template are handled" do
    @owner.update_columns(confirmed_at: nil)
    post recipe_admin_automations_path(key: "quote_follow_up")
    assert_match "Confirm your email", flash[:alert]
    assert_empty rules
    @owner.update_columns(confirmed_at: Time.current)
    post admin_automations_path, params: { automation_rule: rule_params(conditions: { client_tag: %w[a b] }, actions: { tag_client: { on: "1", tag: %w[x y] } }) }
    assert_response :unprocessable_content, "array values aren't kept, so the tag step has no tag"
    post admin_automations_path, params: { automation_rule: rule_params(delay_amount: "91", delay_unit: "days") }
    assert_select "[role=alert]", /can be up to 90 days/
    post admin_automations_path, params: { automation_rule: rule_params }
    rule = rules.last
    as_business(@business) { @template.destroy! }
    get edit_admin_automation_path(rule)
    assert_select "option[selected]", /deleted template/
    patch toggle_admin_automation_path(rule)
    assert_not rule.reload.enabled?, "a rule whose template was deleted can still be turned off"
  end

  test "the plan's limit on active automations: turning one on past it says so" do
    3.times { |i| post admin_automations_path, params: { automation_rule: rule_params(name: "Rule #{i}") } }
    as_business(@business) { AutomationRule.last.update!(enabled: false) }
    post admin_automations_path, params: { automation_rule: rule_params(name: "Fourth") }
    off = rules.find { !_1.enabled? }
    patch toggle_admin_automation_path(off)
    assert_not off.reload.enabled?
    assert_match "includes 3 active automations", flash[:alert]
  end

  test "activity is listed on the page and on the record, without client names" do
    quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      AutomationRule.create!(name: "Tell the office", trigger: "quote_sent", actions: [ { "type" => "notify_team", "team" => "office" } ])
      Quote.start(client: maria).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.save!
      end
    end
    perform_enqueued_jobs(only: AutomationRunJob) { as_business(@business) { quote.mark_sent!(by: @owner, channel: "link") } }
    get admin_automations_path
    assert_select "[id^=automation-run-]", /Tell the office for #{quote.number}.*Notified 1 person.*Done/m
    get admin_quote_path(quote)
    assert_select "#automation-runs", /Tell the office.*Notified 1 person/m
  end

  test "on a paid plan without automations, the banner names the plan that has them (#289)" do
    Plan.create!(key: "pro", name: "Pro", public: true, position: 5, monthly_price_cents: 4900, annual_price_cents: 49_000, limits: {}, features: { "automations" => true })
    @business.update!(plan: plans(:starter), plan_overrides: {})
    get admin_automations_path
    assert_select ".banner", /View only on Starter\. Automations come with Pro and up\./
  end

  test "without the plan feature the page explains, history stays, and nothing can be changed" do
    rule = as_business(@business) { AutomationRule.create!(name: "Kept", trigger: "quote_sent", actions: [ { "type" => "notify_team", "team" => "office" } ]) }
    @business.update!(plan_overrides: {})
    get admin_automations_path
    assert_select ".banner", /View only on Free\. Automations come with a bigger plan.*paused/m
    assert_select "#automation-#{rule.uid}", /Kept/
    assert_select "#recipe-quote_follow_up", count: 0
    get new_admin_automation_path
    assert_redirected_to admin_automations_path
    patch toggle_admin_automation_path(rule)
    assert rule.reload.enabled?
  end

  test "only people who manage settings see automations, and another business's are not found" do
    theirs = as_business(businesses(:two)) do
      AutomationRule.create!(name: "Theirs", trigger: "quote_sent", actions: [ { "type" => "notify_team", "team" => "office" } ])
    end
    assert_not_found_across_businesses { get edit_admin_automation_path(theirs) }
    assert_not_found_across_businesses { patch toggle_admin_automation_path(theirs) }
    assert_not_found_across_businesses { delete admin_automation_path(theirs) }
    post switch_admin_business_path, params: { business: businesses(:two).uid } # user one is a technician there
    get admin_automations_path
    assert_response :forbidden
  end
end
