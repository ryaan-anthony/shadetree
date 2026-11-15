# Client links and invitations carry their credential in the URL path (/c/:token). Rails only
# filters query parameters, so this request logger also blanks those path segments in the
# "Started GET …" line. Controller logs already filter the :token parameter.
class SecretPathLogger < Rails::Rack::Logger
  SECRET_PATH = %r{(/(?:c|invitations)/)[^/?"]+}

  def self.redact(path) = path.to_s.gsub(SECRET_PATH, '\1[FILTERED]')

  private

  def started_request_message(request)
    self.class.redact(super)
  end
end
