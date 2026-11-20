require "test_helper"

# PLT-10: /up/jobs tells the external uptime check when background work has stopped.
class JobHealthEndpointTest < ActionDispatch::IntegrationTest
  include SolidQueueTables

  test "ok without Solid Queue, and while due jobs are being picked up" do
    get job_health_check_path
    assert_response :success
    assert_equal "ok", response.body

    with_solid_queue_tables do
      enqueue_solid_queue_job
      get job_health_check_path
      assert_equal "ok", response.body
    end
  end

  test "503 when the oldest due job has waited too long, saying nothing more" do
    with_solid_queue_tables do
      enqueue_solid_queue_job("ClientMailDeliveryJob")
      SolidQueue::ReadyExecution.update_all(created_at: 11.minutes.ago)
      get job_health_check_path
      assert_response :service_unavailable
      assert_equal "stalled", response.body
    end
  end
end
