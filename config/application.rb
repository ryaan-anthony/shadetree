require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Shadetree
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    # Lets a locale give an attribute its own full-message format ("%{message}"), for messages
    # shown to clients and the public as written. Attributes without one keep Rails' format.
    config.active_model.i18n_customize_full_message = true
    # OPS-05: email to support arrives through our own signed ingress (InboundEmailIngress), never
    # Action Mailbox's built-in ingresses, which stay switched off (no config.action_mailbox.ingress).
    # Raw messages go 14 days after processing (PurgeInboundEmailsJob catches any left behind).
    config.action_mailbox.incinerate_after = 14.days

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks secret_path_logger.rb observability observability.rb server_tls.rb forwarded_headers.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # MKT-04: analytics (Analytics) only outside development and test.
    config.x.analytics = !Rails.env.local?
  end
end
