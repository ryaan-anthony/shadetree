ENV["RAILS_ENV"] ||= "test"

# Coverage must start before any application code loads. Set COVERAGE=false to skip it locally.
unless ENV["COVERAGE"] == "false"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
  end
end

require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

# Rails 8 loads routes lazily; Devise builds its user mappings when routes load. Load them up
# front so tests that sign users in before the first request don't fail intermittently.
Rails.application.reload_routes_unless_loaded

# Include Devise test helpers
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # The hidden fields a public form sends (AbuseProtection, PLT-13), as if opened 10 seconds ago.
  def form_guard_params(purpose, at: 10.seconds.ago)
    { website: "", form_token: Rails.application.message_verifier("form_guard").generate(at.to_f, purpose:, expires_in: 1.day) }
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
