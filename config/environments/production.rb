require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Uploaded files on local disk: storage/ is a Docker volume on the VM, included in the backups
  # (ADR 0023, ops/backup).
  config.active_storage.service = :local

  # All access comes through the Cloudflare tunnel over HTTPS (ADR 0023).
  config.assume_ssl = true

  # Only the tunnel connector (TRUSTED_PROXIES) may say who the visitor is; nobody may name another
  # host (lib/forwarded_headers.rb). Without it every visitor would share the connector's address.
  require Rails.root.join("lib/forwarded_headers").to_s
  config.action_dispatch.trusted_proxies = ForwardedHeaders.proxies(ENV["TRUSTED_PROXIES"])
  config.middleware.insert_before 0, ForwardedHeaders, trusted: config.action_dispatch.trusted_proxies

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs: /up here, and the uptime check's /up/jobs and
  # /up/backup (PLT-09, PLT-10) the same way.
  config.silence_healthcheck_path = "/up"
  %w[/up/jobs /up/backup].each { config.middleware.insert_before Rails::Rack::Logger, Rails::Rack::SilenceRequest, path: _1 }

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # Transactional email over SMTP (ADR 0017, NTF-01), configured per environment: production
  # uses the provider's credentials, staging its sandbox credentials. Without SMTP_ADDRESS
  # nothing is sent (rather than trying localhost); client emails show "Couldn't send" and
  # config/initializers/mail_settings.rb warns at boot.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.raise_delivery_errors = true # ClientMailDeliveryJob sorts the errors
    port = ENV.fetch("SMTP_PORT", 587).to_i
    # Encryption is required, never just attempted: implicit TLS on 465, STARTTLS otherwise.
    encryption = port == 465 ? { tls: true } : { enable_starttls: :always }
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"], port:, user_name: ENV["SMTP_USERNAME"], password: ENV["SMTP_PASSWORD"],
      authentication: :plain, open_timeout: 10, read_timeout: 20, **encryption
    }
  else
    config.action_mailer.perform_deliveries = false
  end
  # Links and images in email (logos, "View quote") point at the public app host (PLT-09).
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "example.com"), protocol: "https" }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Only answer for our own domain (DNS rebinding protection). The health checks (/up, /up/jobs,
  # /up/backup) answer on any host: the deploy checks them on localhost inside the container.
  if ENV["APP_HOST"].present?
    config.hosts << ENV["APP_HOST"]
    config.host_authorization = { exclude: ->(request) { request.path == "/up" || request.path.start_with?("/up/") } }
  end
end
