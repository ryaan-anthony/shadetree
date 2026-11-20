require "test_helper"

# OPS-05: raw support email is gone after 14 days, processed or not, and so is its file.
class PurgeInboundEmailsJobTest < ActiveJob::TestCase
  include InboundEmailHelpers

  def store(at)
    travel_to(at) { ActionMailbox::InboundEmail.create_and_extract_message_id!(raw_email, envelope_to: "support@getshadetree.com") }
  end

  test "removes messages older than 14 days with their raw file, keeps newer ones" do
    old, recent = store(15.days.ago), store(13.days.ago)
    blob = old.raw_email.blob
    perform_enqueued_jobs { PurgeInboundEmailsJob.perform_now }
    assert_not ActionMailbox::InboundEmail.exists?(old.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert ActionMailbox::InboundEmail.exists?(recent.id)
  end

  test "a processed message is incinerated 14 days later" do
    inbound = store(Time.current)
    assert_enqueued_with(job: ActionMailbox::IncinerationJob) { inbound.delivered! }
    travel(15.days) { perform_enqueued_jobs(only: ActionMailbox::IncinerationJob) }
    assert_not ActionMailbox::InboundEmail.exists?(inbound.id)
  end
end
