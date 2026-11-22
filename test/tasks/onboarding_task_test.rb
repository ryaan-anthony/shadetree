require "test_helper"
require "rake"

# ACC-08: the guided tour's product measurement, beside ACC-05's time to first quote.
class OnboardingTaskTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("onboarding:tour") }

  test "the measurement task reports outcomes and stops, with no personal data" do
    business_users(:one).update!(tour_status: "skipped", tour_stop: "quotes", tour_offered_at: 1.hour.ago)
    business_users(:two).update!(tour_status: "finished", tour_stop: "settings", tour_offered_at: 1.hour.ago)
    output = capture_io { Rake::Task["onboarding:tour"].execute }.first
    assert_match(/New businesses.*\n  finished: 1\./, output)
    assert_match(/skipped: 1\./, output)
    assert_match "Ended or left at: quotes 1.", output
    assert_no_match(/@|#{users(:one).first_name}/, output)
  end

  test "existing businesses' Owners are reported apart, timed from the offer (owner, 2026-11-22)" do
    old = businesses(:one)
    old.update_columns(created_at: 60.days.ago, first_quote_sent_at: 2.hours.ago)
    business_users(:one).update!(tour_status: "finished", tour_stop: "settings", tour_offered_at: 3.hours.ago)
    businesses(:two).update_columns(created_at: 2.days.ago, first_quote_sent_at: 2.days.ago + 30.minutes)
    business_users(:two).update!(tour_status: "skipped", tour_stop: "offer", tour_offered_at: 2.days.ago + 1.minute)
    output = capture_io { Rake::Task["onboarding:tour"].execute }.first
    assert_match(/New businesses.*\n  skipped: 1\. 30\.0 min to first quote/, output)
    assert_match(/Existing businesses.*\n  finished: 1\. 60\.0 min to first quote/, output, "from the offer, not from 60 days ago")
  end
end
