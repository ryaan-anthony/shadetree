# PLT-10: what the app tells us about itself. Errors from requests and jobs reach Rails.error with
# their context (Observability::ErrorContext), are logged as one JSON line each
# (Observability::ErrorSubscriber) and handed to Observability.tracker; requests and jobs log one
# JSON line each (Observability::LogSubscriber); slow requests and queries are flagged. Nothing
# here may carry client personal data: context is filtered with config.filter_parameters and
# free text is scrubbed of email addresses and phone-like numbers. See
# docs/security/personal-data-inventory.md.
module Observability
  # An operational problem worth a look (a failed job, a growing queue), reported through
  # Rails.error like an exception so it takes the same road to the logs and the tracker.
  class Alert < StandardError; end

  # THE hook for the error tracker (PLT-10 open question: hosted or self-hosted, not chosen yet).
  # Anything that responds to call(error, payload) gets every report after it has been logged;
  # payload is the sanitized hash that was logged. Set it in config/initializers/observability.rb.
  # A tracker whose SDK subscribes to Rails.error itself also gets the sanitized context, since
  # ErrorContext runs before every subscriber; give it Observability.scrub for messages.
  mattr_accessor :tracker

  EMAIL = /[^\s@<>()"'=,;:]+@[^\s@<>()"'=,;:]+\.[a-z]{2,}/i
  NUMBER = /\+?\d[\d\s().-]{6,}\d/
  SQL_STRING = /'(?:[^']|'')*'/

  class << self
    def config = Rails.configuration.x.observability
    def structured_logs? = config.structured_logs == true

    # The deployed version: Kamal sets KAMAL_VERSION (the commit) in the container (PLT-09).
    def release = ENV["APP_REVISION"].presence || ENV["KAMAL_VERSION"].presence || "development"

    def alert(message, **details)
      Rails.error.report(Alert.new(message), handled: true, severity: :warning, context: details, source: "shadetree.alert")
    end

    # Free text (exception messages) with email addresses and phone-like numbers masked.
    def scrub(text, limit: 500)
      text.to_s.gsub(EMAIL, "[EMAIL]").gsub(NUMBER, "[NUMBER]").truncate(limit)
    end

    # SQL with its literal strings removed (values normally travel as binds; this catches the rest).
    def scrub_sql(sql) = sql.to_s.gsub(SQL_STRING, "'?'").squish.truncate(1000)

    # A hash with every sensitive key masked (config.filter_parameters) and strings scrubbed.
    def sanitize(hash)
      parameter_filter.filter(hash.to_h).transform_values { _1.is_a?(String) ? scrub(_1) : _1 }
    end

    def log(level, event, **fields)
      Rails.logger.public_send(level, { event:, **fields }.compact.to_json)
    end

    # Which audience a controller serves, so staff, client and operator pages can be told apart.
    def area(controller)
      return "client" if controller.class.include?(ClientLinkAccess)

      { "Admin" => "staff", "Ops" => "operator" }.fetch(controller.class.module_parent_name.to_s, "public")
    end

    # The request's id, method and path (link tokens blanked) while a controller is running.
    def request_fields(controller = ActiveSupport::ExecutionContext.to_h[:controller])
      return {} unless controller.respond_to?(:request) && controller.request

      request = controller.request
      { request_id: request.request_id, method: request.request_method, path: SecretPathLogger.redact(request.filtered_path) }
    end

    def current_fields
      { business_id: Current.business&.id, user_id: Current.user&.id }.compact
    end

    private

    def parameter_filter
      ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end
  end
end
