require "test_helper"

# PLT-10: the console's home shows failed jobs and the queue where Solid Queue runs.
class Ops::JobHealthCardTest < ActionDispatch::IntegrationTest
  include SolidQueueTables

  test "without Solid Queue the card explains where it shows" do
    sign_in_operator
    get ops_root_path
    assert_select "#job-health", /once the app runs jobs on Solid Queue/
  end

  test "failed jobs and the backlog show with the job classes" do
    sign_in_operator
    with_solid_queue_tables do
      fail_solid_queue_job("QuotePdfJob")
      enqueue_solid_queue_job
      get ops_root_path
      assert_select "#job-health .badge", "Needs a look"
      assert_select "#job-health-failed", "1"
      assert_select "#job-health-backlog", "1"
      assert_select "#job-health", /QuotePdfJob \(1\)/
    end
  end
end
