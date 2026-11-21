source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# PostgreSQL is the database for Active Record and the Solid gems (docs/adr/0002-postgresql.md)
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Authentication
gem "devise"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# PDFs from the client-page HTML with headless Chrome (ADR 0010, QTE-02)
gem "ferrum", "~> 0.17"
gem "image_processing", "~> 1.2"

# Reading client CSV imports (CLI-06); a bundled gem since Ruby 3.4, so it must be listed.
gem "csv"
# QR codes for the request form link (CLI-03); pure Ruby.
gem "rqrcode", "~> 3.1"

# Stripe: plans and subscriptions (BIL-04) and client payments through Connect (PAY-03, PAY-04)
gem "stripe", "~> 21.1"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Emails sent in development open in the browser at /letter_opener (NTF-01, ADR 0017).
  gem "letter_opener_web", "~> 3.0"
end

group :test do
  gem "pdf-reader", "~> 2.14"
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "rails-controller-testing"
  # axe-core's script, run by the system tests' accessibility checks (QA #274)
  gem "axe-core-api", "~> 4.14", require: false

  # Test coverage reporting (CI publishes a summary on every run)
  gem "simplecov", require: false
end

gem "tailwindcss-rails", "~> 4.7"
