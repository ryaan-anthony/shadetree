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

# Rails 8 loads routes lazily; Devise builds its user mappings when routes load. Load them up
# front so tests that sign users in before the first request don't fail intermittently.
Rails.application.reload_routes_unless_loaded

# Include Devise test helpers
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
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
