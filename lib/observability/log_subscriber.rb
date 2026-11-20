# PLT-10: one JSON line per request and per job, from the structured events Rails 8.1 emits
# (Rails.event), plus slow requests and slow queries. With structured logs off (development,
# test) only the slow ones are logged; Rails' usual text lines cover the rest.
#
#   {"event":"request","request_id":"…","method":"GET","path":"/c/[FILTERED]","controller":"ClientLinksController#show",
#    "area":"client","status":200,"duration_ms":41.2,"db_ms":6.1,"view_ms":20.3,"business_id":12}
module Observability
  class LogSubscriber
    LOGGED = "shadetree.request_logged"
    # Retries and discards are handled outcomes (warn); running out of retries is an error.
    JOB_OUTCOMES = { "active_job.retry_scheduled" => [ "job_retry", :warn ], "active_job.discarded" => [ "job_discarded", :warn ],
                     "active_job.retry_stopped" => [ "job_retries_exhausted", :error ] }.freeze

    # A request no controller finished (unknown path, a middleware refused it), from SecretPathLogger.
    def self.unhandled_request(request, status, started)
      return if request.get_header(LOGGED) || !Observability.structured_logs?

      error = request.get_header("action_dispatch.exception")
      Observability.log(status.to_i >= 500 ? :error : :info, "request",
        request_id: request.request_id, method: request.request_method, path: Observability.path(request),
        status: status.to_i, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
        error_class: error&.class&.name)
    end

    def emit(event)
      case event[:name]
      when "action_controller.request_completed" then request(event[:payload])
      when "active_job.completed" then job(event[:payload])
      when *JOB_OUTCOMES.keys then job_outcome(*JOB_OUTCOMES.fetch(event[:name]), event[:payload])
      end
    end

    # Slow queries come from the sql.active_record notification (Rails' structured SQL event is
    # debug-only). Schema lookups and cached queries are skipped.
    def sql(event)
      payload = event.payload
      return if event.duration < Observability.config.slow_query_ms || payload[:name] == "SCHEMA" || payload[:cached]

      Observability.log(:warn, "slow_query", duration_ms: event.duration.round(1), name: payload[:name],
        sql: Observability.scrub_sql(payload[:sql]), source: source_line,
        **Observability.request_fields.slice(:request_id), **Observability.current_fields.slice(:business_id))
    end

    private

    def source_line
      Rails.backtrace_cleaner.clean(caller).find { !_1.start_with?("config/initializers/observability", "lib/observability") }
    end

    def request(payload)
      controller = ActiveSupport::ExecutionContext.to_h[:controller]
      controller&.request&.set_header(LOGGED, true)
      slow = payload[:duration_ms].to_f >= Observability.config.slow_request_ms
      return unless slow || Observability.structured_logs?

      Observability.log(slow ? :warn : :info, "request",
        **Observability.request_fields(controller),
        controller: "#{payload[:controller]}##{payload[:action]}", area: controller && Observability.area(controller),
        status: payload[:status], duration_ms: payload[:duration_ms], db_ms: payload[:db_runtime]&.round(1),
        view_ms: payload[:view_runtime]&.round(1), slow: slow || nil, **Observability.current_fields)
    end

    # The job's own line: an exception here escaped every retry_on/discard_on, so it's an error.
    def job(payload)
      return unless Observability.structured_logs?

      Observability.log(payload[:exception_class] ? :error : :info, "job", **job_fields(payload),
        duration_ms: payload[:duration], **error_fields(payload))
    end

    def job_outcome(event, level, payload)
      return unless Observability.structured_logs?

      Observability.log(level, event, **job_fields(payload), wait_seconds: payload[:wait_seconds], **error_fields(payload))
    end

    def job_fields(payload)
      job = ActiveSupport::ExecutionContext.to_h[:job]
      job = nil unless job&.job_id == payload[:job_id]
      { job_class: payload[:job_class], job_id: payload[:job_id], queue: payload[:queue] || job&.queue_name,
        executions: payload[:executions] || job&.executions, business_id: job.try(:business_id) }
    end

    def error_fields(payload)
      { error_class: payload[:exception_class], error_message: payload[:exception_message]&.then { Observability.scrub(_1) } }
    end
  end
end
