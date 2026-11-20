require "test_helper"
require "rake"

# BIL-04: bin/rails stripe:sync_plans (against the fake gateway; tests never call Stripe).
class StripeTaskTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("stripe:sync_plans") }

  def run_task
    out = StringIO.new
    $stdout, old = out, $stdout
    Rake::Task["stripe:sync_plans"].reenable
    Rake::Task["stripe:sync_plans"].invoke
    out.string
  ensure
    $stdout = old
  end

  test "syncs the plans and says what changed, then that nothing did" do
    output = run_task
    assert_match "Syncing plans to Stripe (test mode)", output
    assert_match "starter: product created", output
    again = run_task
    assert_no_match "created", again
    assert_match "customer portal: settings updated", again
  end

  test "stops without a key" do
    stripe.configured = false
    assert_raises(SystemExit) { capture_io { run_task } }
  end
end
