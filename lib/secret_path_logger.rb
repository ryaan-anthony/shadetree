# Client links and invitations carry their credential in the URL path (/c/:token), and so do
# Active Storage file addresses (signed ids that never expire, then the file's name, which can
# name a client). Rails only filters query parameters, so this request logger also blanks those
# path segments in the "Started GET …" line. Controller logs already filter the :token parameter.
#
# With structured logs on (PLT-10) the "Started" line is skipped: the request's JSON line
# (Observability::LogSubscriber) says what it did, without the client's IP address. Requests no
# controller handled (unknown paths, a middleware's refusal) get their JSON line from here.
class SecretPathLogger < Rails::Rack::Logger
  SECRET_PATH = %r{(/(?:c|invitations)/)[^/?"\s]+|(/rails/active_storage/[^/?"\s]+/)[^?"\s]+}

  def self.redact(path) = path.to_s.gsub(SECRET_PATH) { "#{$1 || $2}[FILTERED]" }

  private

  def started_request_message(request)
    self.class.redact(super)
  end

  # Rails::Rack::Logger#call_app without its "Started" line.
  def call_app(request, env)
    return super unless Observability.structured_logs?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    handle = ActiveSupport::Notifications.instrumenter.build_handle("request.action_dispatch", { request: })
    handle.start
    status, headers, body = response = @app.call(env)
    body = ::Rack::BodyProxy.new(body) do
      Observability::LogSubscriber.unhandled_request(request, status, started)
      finish_request_instrumentation(handle, env["rails.rack_logger_tag_count"])
    end
    response.frozen? ? [ status, headers, body ] : response.tap { _1[2] = body }
  rescue Exception # rubocop:disable Lint/RescueException -- as Rails does: finish, then re-raise
    Observability::LogSubscriber.unhandled_request(request, 500, started)
    finish_request_instrumentation(handle, env["rails.rack_logger_tag_count"]) if handle
    raise
  end
end
