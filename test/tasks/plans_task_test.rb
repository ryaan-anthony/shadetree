require "test_helper"
require "rake"

# BIL-01: the operators' plan commands (until the operator console).
class PlansTaskTest < ActiveSupport::TestCase
  KEYS = %w[PLAN LIMIT FEATURE FIELD VALUE BUSINESS CLEAR].freeze

  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("plans:set") }
  teardown { KEYS.each { ENV.delete(_1) } }

  def run_task(name, **env)
    KEYS.each { ENV.delete(_1) }
    env.each { ENV[_1.to_s.upcase] = _2 }
    Rake::Task[name].reenable
    capture_io { Rake::Task[name].invoke }
  end

  test "set changes limits, features, prices and visibility; a missing or bad value changes nothing" do
    run_task("plans:set", plan: "free", limit: "quotes_sent", value: "10")
    assert_equal 10, plans(:free).reload.limits["quotes_sent"]
    run_task("plans:set", plan: "free", limit: "quotes_sent", value: "unlimited")
    assert_nil plans(:free).reload.limits["quotes_sent"]
    run_task("plans:set", plan: "starter", field: "monthly_price", value: "24")
    assert_equal 2_400, plans(:starter).reload.monthly_price_cents
    assert_raises(SystemExit) { run_task("plans:set", plan: "free", limit: "team_members") }
    assert_equal 2, plans(:free).reload.limits["team_members"]
    assert_raises(SystemExit) { run_task("plans:set", plan: "starter", field: "public", value: "nope") }
    assert_raises(ActiveRecord::RecordInvalid) { run_task("plans:set", plan: "starter", feature: "sms", value: "yes") }
  end

  test "comp overrides one business, and refuses values that would break its pages" do
    business = businesses(:one)
    run_task("plans:comp", business: business.uid, limit: "quotes_sent", value: "50")
    assert_equal 50, business.reload.entitlements.limit(:quotes_sent)
    assert_raises(ActiveRecord::RecordInvalid) { run_task("plans:comp", business: business.uid, limit: "team_members", value: "ten") }
    run_task("plans:comp", business: business.uid, limit: "quotes_sent", clear: "1")
    assert_equal 5, business.reload.entitlements.limit(:quotes_sent)
  end
end
