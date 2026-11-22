# PLT-10, ADR 0027: the error tracker is Sentry (free Developer plan), and only when SENTRY_DSN is
# set (staging and production). Without it nothing here runs and nothing leaves the app.
#
# One road in: Observability::ErrorSubscriber hands every Rails.error report (unhandled request and
# job exceptions, the handled ones the app reports, Observability.alert) to #call, with the payload
# ErrorContext already sanitized. sentry-rails' own captures (its Rack middleware, its Active Job
# extension, its Rails.error subscriber) are switched off, so no event is built from a request's
# params, headers or cookies or from a job's arguments.
#
# Then .scrub, as before_send, on everything that leaves anyway: no request, user details,
# breadcrumbs or frame variables; context, tags and extra masked by config.filter_parameters plus
# PRIVATE_KEYS; exception values and messages through Observability.scrub (no emails, phone-like
# numbers, database row details) with SQL literals removed. The business travels as its id only.
module Observability
  class SentryTracker
    # Keys masked anywhere in an event, beyond config.filter_parameters (partial matches, as there).
    PRIVATE_KEYS = %i[
      name email phone mobile address street city postal zip body notes note instructions description
      message subject comment signer contact token secret password passw cookie session authorization
      ip_address remote_ip arguments params query
    ].freeze
    # Who an event is about, in tags: ids and labels only, never anything a client typed.
    TAG_KEYS = %i[source handled area job_class queue business_id].freeze
    # Sentry's own description of the machine and Ruby, left as they are.
    SDK_CONTEXTS = %i[os runtime trace].freeze
    SQL = /\b(?:SELECT|INSERT|UPDATE|DELETE|WITH)\b/i
    LEVELS = { error: :error, warning: :warning, info: :info }.freeze

    class << self
      def enabled? = dsn.present?
      def dsn = ENV["SENTRY_DSN"].presence

      # staging or production; SENTRY_ENVIRONMENT overrides the deploy's APP_ENVIRONMENT.
      def environment = ENV["SENTRY_ENVIRONMENT"].presence || ENV["APP_ENVIRONMENT"].presence || Rails.env

      # Every Sentry setting in one place, for the initializer and the tests.
      def configure(config, dsn: self.dsn)
        config.dsn = dsn
        config.environment = environment
        config.release = Observability.release
        config.send_default_pii = false
        config.data_collection.http_headers.request.mode = :off
        config.data_collection.http_headers.response.mode = :off
        config.data_collection.database_query_data = false
        config.data_collection.queues = false
        config.data_collection.frame_context_lines = 0 # no source lines: file and line number only
        config.breadcrumbs_logger = []
        config.max_breadcrumbs = 0
        config.before_breadcrumb = ->(*) { nil }
        # Errors only: no tracing, profiling or logs, so the free plan's span quota isn't touched.
        config.traces_sample_rate = 0.0
        config.profiles_sample_rate = 0.0 if config.respond_to?(:profiles_sample_rate=)
        config.enable_logs = false if config.respond_to?(:enable_logs=)
        config.auto_session_tracking = false
        config.send_modules = false
        config.rails.register_error_subscriber = false
        config.rails.report_rescued_exceptions = false
        config.rails.skippable_job_adapters = job_adapters
        config.before_send = ->(event, hint) { scrub(event, hint) }
      end

      # Every Active Job adapter, so sentry-rails' job extension never captures or tags a job itself.
      def job_adapters
        names = ActiveJob::QueueAdapters.constants.grep(/Adapter\z/).map { "ActiveJob::QueueAdapters::#{_1}" }
        (names + %w[ActiveJob::QueueAdapters::SolidQueueAdapter ActiveJob::QueueAdapters::TestAdapter]).uniq
      end

      def scrub(event, hint = {})
        event.instance_variable_set(:@request, nil)
        event.user = event.user.to_h.slice(:id, "id")
        event.breadcrumbs&.buffer&.clear
        event.server_name = nil
        event.message = scrub_text(event.message) if event.message.is_a?(String)
        event.message = event.message.merge(formatted: scrub_text(event.message[:formatted])) if event.message.is_a?(Hash)
        event.tags = sanitize(event.tags)
        event.extra = sanitize(event.extra)
        event.contexts = event.contexts.to_h.except(*SDK_CONTEXTS).then { sanitize(_1) }.merge(event.contexts.to_h.slice(*SDK_CONTEXTS))
        scrub_exceptions(event, hint.to_h[:exception]) if event.respond_to?(:exception) && event.exception
        event
      end

      def scrub_text(text)
        text = text.to_s
        text = text.gsub(SQL_STRING, "'?'") if text.match?(SQL)
        Observability.scrub(text, limit: 1000)
      end

      private

      # Values are the plain messages (Ruby's detailed_message adds source lines), scrubbed; frames
      # keep file, line and function only. Sentry lists the cause chain innermost first.
      def scrub_exceptions(event, error)
        chain = error ? Sentry::Utils::ExceptionCauseChain.exception_to_array(error).reverse : []
        event.exception.values.each_with_index do |exception, index|
          exception.value = scrub_text(chain[index]&.message || exception.value)
          exception.stacktrace&.frames&.each do |frame|
            frame.vars = frame.pre_context = frame.context_line = frame.post_context = nil
          end
        end
      end

      def sanitize(hash)
        filter.filter(hash.to_h).transform_values { scrub_value(_1) }
      end

      def scrub_value(value)
        case value
        when String then scrub_text(value)
        when Hash then value.transform_values { scrub_value(_1) }
        when Array then value.map { scrub_value(_1) }
        else value
        end
      end

      def filter
        @filter = nil if @filter_source != Rails.application.config.filter_parameters
        @filter_source = Rails.application.config.filter_parameters
        @filter ||= ActiveSupport::ParameterFilter.new(@filter_source + PRIVATE_KEYS)
      end
    end

    # Observability.tracker: payload is ErrorSubscriber's (scrubbed message, location, release,
    # environment, request or job fields, business and user ids, the caller's sanitized context).
    def call(error, payload)
      return unless Sentry.initialized?

      level = LEVELS.fetch(payload[:severity], :error)
      tags = payload.slice(*TAG_KEYS).compact.transform_values(&:to_s)
      context = payload.except(:message, :backtrace, :location, :severity, *TAG_KEYS)
      if error.is_a?(Alert)
        # Same message, same issue: alerts are grouped by what went wrong, not by their counts.
        Sentry.capture_message(error.message, level:, tags:, contexts: { shadetree: context }, fingerprint: [ "alert", error.message ])
      else
        Sentry.capture_exception(error, level:, tags:, contexts: { shadetree: context })
      end
    end

    # A Sentry Cron check-in (the free plan has one monitor): :ok or :error, and a missed one when
    # the check didn't run at all (workers or dispatcher down).
    def check_in(slug, status, every_minutes:)
      return unless Sentry.initialized?

      config = Sentry::Cron::MonitorConfig.from_interval(every_minutes, :minute, checkin_margin: every_minutes, max_runtime: 5)
      Sentry.capture_check_in(slug, status, monitor_config: config)
    end
  end
end
