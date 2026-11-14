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
      business = Business.find(job.business_id)
      Tenancy.with_business(business) { block.call }
    else
      block.call
    end
  end

  def serialize
    super.merge("business_id" => business_id)
  end

  def deserialize(job_data)
    super
    self.business_id = job_data["business_id"]
  end
end
