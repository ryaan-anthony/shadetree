# OPS-05: raw support email is kept 14 days. Action Mailbox incinerates each message 14 days
# after it's processed; this daily sweep removes any older one that never was (a lost job, a
# crash), with its raw file.
class PurgeInboundEmailsJob < ApplicationJob
  def perform
    ActionMailbox::InboundEmail.where(created_at: ...ActionMailbox.incinerate_after.ago).find_each(&:destroy!)
  end
end
