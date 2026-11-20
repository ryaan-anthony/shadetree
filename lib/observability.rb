# PLT-10: what the app tells us about itself. Errors from requests and jobs reach Rails.error with
# their context (Observability::ErrorContext), are logged as one JSON line each
# (Observability::ErrorSubscriber) and handed to Observability.tracker; requests and jobs log one
# JSON line each (Observability::LogSubscriber); slow requests and queries are flagged. Nothing
# here may carry client personal data: context is filtered with config.filter_parameters and
# free text loses database row details, email addresses and phone-like numbers. See
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

  EMAIL = /[^\s@<>()"'=,;:\/]+(?:@|%40)[^\s@<>()"'=,;:\/&?]+\.[a-z]{2,}/i
  # A run of digits shaped like a phone number: 7 to 15 digits, optionally grouped by spaces, dots,
  # dashes or brackets, not glued to other characters (so ids after "id=", times, UUID tails and
  # file names stay); dates and IP addresses are let through below.
  PHONE = %r{(?<![\w.:/%=#-])\+?\(?\d[\d ().-]{5,}\d(?![\w.:/%-])}
  NOT_PHONE = /\A(?:\d{4}-\d{2}-\d{2}|\d{1,3}(?:\.\d{1,3}){3}\z)/
  # Postgres appends the row or key values that broke a constraint ("DETAIL:  Failing row
  # contains (…)", "Key (email)=(…)"); everything from DETAIL or HINT on is dropped.
  DETAIL = /\s*\b(?:DETAIL|HINT):.*/m
  SQL_STRING = /'(?:[^']|'')*'/

  class << self
    def config = Rails.configuration.x.observability
    def structured_logs? = config.structured_logs == true

    # Settings from the environment: blank means the default; numbers are decimal.
    def env_integer(name, default) = ENV[name].present? ? Integer(ENV[name], 10) : default
    def env_flag(name, default) = ENV[name].present? ? ActiveModel::Type::Boolean.new.cast(ENV[name]) : default

    # The deployed version: the deploy sets APP_REVISION to the commit (PLT-09, ops/deploy).
    def release = ENV["APP_REVISION"].presence || "development"

    # STRUCTURED_LOGS: one JSON line per request and job replaces Rails' text lines, whose
    # messages can carry values (an exception message, a mail server's reply quoting an address)
    # and the client IP; every line, ours or not, is written as JSON (JsonLogFormatter).
    def structure_logs!(config)
      config.action_dispatch.debug_exception_log_level = :debug
      ActiveSupport.on_load(:action_controller) { ActionController::LogSubscriber.detach_from(:action_controller) }
      ActiveSupport.on_load(:action_view) { ActionView::LogSubscriber.detach_from(:action_view) }
      ActiveSupport.on_load(:active_job) { ActiveJob::LogSubscriber.detach_from(:active_job) }
      ActiveSupport.on_load(:action_mailer) { ActionMailer::LogSubscriber.detach_from(:action_mailer) }
      loggers = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts : [ Rails.logger ]
      loggers.each { _1.formatter = JsonLogFormatter.new }
    end

    def alert(message, **details)
      Rails.error.report(Alert.new(message), handled: true, severity: :warning, context: details, source: "shadetree.alert")
    end

    # Free text (exception messages) without database row details, email addresses or
    # phone-like numbers.
    def scrub(text, limit: 500)
      text.to_s.sub(DETAIL, "").gsub(EMAIL, "[EMAIL]")
        .gsub(PHONE) { |match| phone?(match) ? "[NUMBER]" : match }
        .truncate(limit)
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
      { request_id: request.request_id, method: request.request_method, path: path(request) }
    end

    # A request's path with query secrets, link tokens, file ids and email addresses blanked.
    def path(request) = scrub(SecretPathLogger.redact(request.filtered_path))

    def current_fields
      { business_id: Current.business&.id, user_id: Current.user&.id }.compact
    end

    private

    # Grouped numbers need 7 digits (555-0100 style), bare ones 10 (an id is rarely that long).
    def phone?(match)
      digits = match.count("0-9")
      digits <= 15 && digits >= (match.match?(/\A\d+\z/) ? 10 : 7) && !match.match?(NOT_PHONE)
    end

    def parameter_filter
      ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end
  end
end
