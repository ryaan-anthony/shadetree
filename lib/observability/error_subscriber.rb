# PLT-10: every Rails.error report (unhandled request and job exceptions, the handled ones the app
# reports itself, and Observability.alert) becomes one JSON log line, then goes to the tracker hook.
module Observability
  class ErrorSubscriber
    LEVELS = { error: :error, warning: :warn, info: :info }.freeze

    def report(error, handled:, severity:, context:, source:)
      payload = {
        error_class: error.class.name, message: Observability.scrub(error.message),
        location: backtrace(error).first, backtrace: backtrace(error).first(10), handled:, severity:, source:, **context
      }
      Observability.log(LEVELS.fetch(severity, :warn), error.is_a?(Alert) ? "alert" : "error", **payload)
      Observability.tracker&.call(error, payload)
    end

    private

    # Our own code's frames, relative to the app (the raw first frame if none are ours).
    def backtrace(error)
      frames = Array(error.backtrace)
      Rails.backtrace_cleaner.clean(frames).presence || frames.first(1).map { _1.delete_prefix("#{Rails.root}/") }
    end
  end
end
