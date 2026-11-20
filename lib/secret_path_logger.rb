# Client links and invitations carry their credential in the URL path (/c/:token). Rails only
# filters query parameters, so this request logger also blanks those path segments in the
# "Started GET …" line. Controller logs already filter the :token parameter.
#
# With structured logs on (PLT-10) the "Started" line is skipped altogether: the request's JSON
# line (Observability::LogSubscriber) says everything it did, without the client's IP address.
class SecretPathLogger < Rails::Rack::Logger
  SECRET_PATH = %r{(/(?:c|invitations)/)[^/?"]+}

  def self.redact(path) = path.to_s.gsub(SECRET_PATH, '\1[FILTERED]')

  private

  def started_request_message(request)
    self.class.redact(super)
  end

  # Rails::Rack::Logger#call_app without its "Started" line.
  def call_app(request, env)
    return super unless Observability.structured_logs?

    handle = ActiveSupport::Notifications.instrumenter.build_handle("request.action_dispatch", { request: })
    handle.start
    status, headers, body = response = @app.call(env)
    body = ::Rack::BodyProxy.new(body) { finish_request_instrumentation(handle, env["rails.rack_logger_tag_count"]) }
    response.frozen? ? [ status, headers, body ] : response.tap { _1[2] = body }
  rescue Exception # rubocop:disable Lint/RescueException -- as Rails does: finish, then re-raise
    finish_request_instrumentation(handle, env["rails.rack_logger_tag_count"]) if handle
    raise
  end
end
