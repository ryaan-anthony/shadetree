# PLT-10: one JSON line per request and per job, from the structured events Rails 8.1 emits
# (Rails.event), plus slow requests and slow queries. With structured logs off (development,
# test) only the slow ones are logged; Rails' usual text lines cover the rest.
#
#   {"event":"request","request_id":"…","method":"GET","path":"/c/[FILTERED]","controller":"ClientLinksController#show",
#    "area":"client","status":200,"duration_ms":41.2,"db_ms":6.1,"view_ms":20.3,"business_id":12}
module Observability
  class LogSubscriber
    def emit(event)
      case event[:name]
      when "action_controller.request_completed" then request(event[:payload])
      when "active_job.completed" then job(event[:payload])
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
      slow = payload[:duration_ms].to_f >= Observability.config.slow_request_ms
      return unless slow || Observability.structured_logs?

      controller = ActiveSupport::ExecutionContext.to_h[:controller]
      Observability.log(slow ? :warn : :info, "request",
        **Observability.request_fields(controller),
        controller: "#{payload[:controller]}##{payload[:action]}", area: controller && Observability.area(controller),
        status: payload[:status], duration_ms: payload[:duration_ms], db_ms: payload[:db_runtime]&.round(1),
        view_ms: payload[:view_runtime]&.round(1), slow: slow || nil, **Observability.current_fields)
    end

    def job(payload)
      return unless Observability.structured_logs?

      job = ActiveSupport::ExecutionContext.to_h[:job]
      Observability.log(payload[:exception_class] ? :error : :info, "job",
        job_class: payload[:job_class], job_id: payload[:job_id], queue: payload[:queue], duration_ms: payload[:duration],
        executions: job&.executions, business_id: job.try(:business_id), error_class: payload[:exception_class],
        error_message: payload[:exception_message] && Observability.scrub(payload[:exception_message]))
    end
  end
end
