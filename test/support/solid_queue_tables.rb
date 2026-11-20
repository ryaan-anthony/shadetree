# PLT-10: Solid Queue's tables live in their own database in production and don't exist in test.
# These helpers create them for one test, inside its transaction, so they vanish afterwards.
module SolidQueueTables
  def with_solid_queue_tables
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Schema.verbose = false
      silence_warnings { load Rails.root.join("db/queue_schema.rb") }
      yield
      raise ActiveRecord::Rollback
    end
  end

  def enqueue_solid_queue_job(class_name = "QuotePdfJob")
    SolidQueue::Job.create!(queue_name: "default", class_name:, arguments: {})
  end

  def fail_solid_queue_job(class_name, at: Time.current)
    job = enqueue_solid_queue_job(class_name)
    job.ready_execution&.destroy!
    SolidQueue::FailedExecution.create!(job:, error: { exception_class: "RuntimeError", message: "boom" }, created_at: at)
  end
end
