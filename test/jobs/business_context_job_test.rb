require "test_helper"

class BusinessContextJobTest < ActiveJob::TestCase
  class RecordContextJob < ApplicationJob
    cattr_accessor :seen

    def perform = self.class.seen = [ Current.business, Time.zone.tzinfo.identifier ]
  end

  test "jobs run as the business that enqueued them, in its time zone" do
    business = businesses(:two)
    as_business(business) { RecordContextJob.perform_later }
    assert_nil Current.business

    perform_enqueued_jobs
    assert_equal [ business, "America/Los_Angeles" ], RecordContextJob.seen
  end

  test "jobs enqueued without a business run without one" do
    RecordContextJob.perform_later
    perform_enqueued_jobs
    assert_nil RecordContextJob.seen.first
  end

  test "the business id survives serialization" do
    job = as_business(businesses(:one)) { RecordContextJob.perform_later }
    copy = RecordContextJob.new
    copy.deserialize(job.serialize)
    assert_equal businesses(:one).id, copy.business_id
  end
end
