# PLT-10: with structured logs on, every log line is one JSON object, so a log shipper can parse
# all of them. Our own lines (Observability.log) are merged in; anything else Rails or the app
# logs becomes {"message": …}. Tags (ActiveJob's job class and id, and the like) go in "tags"
# instead of a "[tag] " prefix that would break the JSON.
#
#   {"time":"2026-11-19T10:00:00.123Z","level":"INFO","tags":["ActiveJob","QuotePdfJob","…"],"event":"job",…}
module Observability
  class JsonLogFormatter < ::Logger::Formatter
    include ActiveSupport::TaggedLogging::Formatter

    def call(severity, time, _progname, message)
      text = message.is_a?(String) ? message : message.inspect
      fields = (JSON.parse(text) if text.start_with?('{"event":')) rescue nil # rubocop:disable Style/RescueModifier
      { time: time.utc.iso8601(3), level: severity, tags: current_tags.presence, **(fields || { message: text.strip }) }.to_json << "\n"
    end
  end
end
