# Keep link tokens out of request logs (PLT-12). See lib/secret_path_logger.rb.
require Rails.root.join("lib/secret_path_logger").to_s
Rails.application.config.middleware.swap Rails::Rack::Logger, SecretPathLogger
