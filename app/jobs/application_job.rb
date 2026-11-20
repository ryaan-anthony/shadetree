class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Jobs run as the business that enqueued them (ADR 0014): Current.business is captured at
  # enqueue time and restored, with its time zone, around perform.
  attr_accessor :business_id

  before_enqueue { self.business_id ||= Current.business&.id }

  around_perform do |job, block|
    if job.business_id
      business = Business.find_by(id: job.business_id)
      # OPS-04: the business was deleted since; its work has nothing left to act on.
      next Rails.logger.info("Discarded #{job.class.name} #{job.job_id}: business #{job.business_id} no longer exists") unless business

      Tenancy.with_business(business) { block.call }
    else
      block.call
    end
  end

  # PLT-10: a failure no retry_on/discard_on handles reaches Rails.error here, whichever adapter
  # runs the job (Solid Queue reports it too; Rails.error reports each exception once).
  # Observability::ErrorContext adds the job class, id and business.
  def perform_now
    super
  rescue => error
    Rails.error.report(error, handled: false, source: "application.active_job")
    raise
  end

  def serialize
    super.merge("business_id" => business_id)
  end

  def deserialize(job_data)
    super
    self.business_id = job_data["business_id"]
  end
end
