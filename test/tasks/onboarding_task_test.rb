require "test_helper"
require "rake"

# ACC-08: the guided tour's product measurement, beside ACC-05's time to first quote.
class OnboardingTaskTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("onboarding:tour") }

  test "the measurement task reports outcomes and stops, with no personal data" do
    business_users(:one).update!(tour_status: "skipped", tour_stop: "quotes", tour_offered_at: 1.hour.ago)
    business_users(:two).update!(tour_status: "finished", tour_stop: "settings", tour_offered_at: 1.hour.ago)
    output = capture_io { Rake::Task["onboarding:tour"].execute }.first
    assert_match(/finished: 1\./, output)
    assert_match(/skipped: 1\./, output)
    assert_match "Ended or left at: quotes 1.", output
    assert_no_match(/@|#{users(:one).first_name}/, output)
  end
end
