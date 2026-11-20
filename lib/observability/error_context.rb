# PLT-10: runs on every Rails.error report, before any subscriber (the log line, a tracker SDK).
# Adds release, environment, request, business and job, and replaces the controller and job
# objects Rails puts in the context with plain ids, so no subscriber can serialize their params,
# arguments or records. In what the caller passed, sensitive keys are masked and text scrubbed.
module Observability
  class ErrorContext
    def call(_error, context:, **)
      context = context.dup
      controller = context.delete(:controller)
      job = context.delete(:job)

      fields = { release: Observability.release, environment: Rails.env }
      fields.merge!(Observability.request_fields(controller)) if controller
      fields.merge!(job_fields(job)) if job.is_a?(ActiveJob::Base)
      fields.merge!(Observability.current_fields) { |_key, from_job, _current| from_job }

      fields.merge(Observability.sanitize(context.transform_values { plain(_1) }))
    end

    private

    def job_fields(job)
      { job_class: job.class.name, job_id: job.job_id, queue: job.queue_name, executions: job.executions,
        business_id: job.try(:business_id) }.compact
    end

    # Records and other objects become global ids or class names, never their inspect output.
    def plain(value)
      case value
      when nil, true, false, Numeric, String, Symbol then value
      when GlobalID::Identification then value.to_global_id.to_s
      when Array then value.map { plain(_1) }
      when Hash then value.transform_values { plain(_1) }
      else value.class.name
      end
    end
  end
end
