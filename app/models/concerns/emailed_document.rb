# A quote (QTE-04) or invoice (PAY-02) that goes to its client by email, and what became of
# that email. Only the latest email counts: a later send that went through settles an earlier
# problem. The document's status stays as it is (a quote stays "Sent"): the client's link
# still works, so the team is warned and resends instead (QA #274, owner decision 2026-11-21).
module EmailedDocument
  extend ActiveSupport::Concern

  def latest_email = latest_email_send&.email_message

  # The email to warn about: the latest one didn't arrive, the client hasn't answered or paid
  # yet (after that, it's history in the sends list), and staff haven't copied the link since.
  def undelivered_email
    email = latest_problem_email
    email unless email.nil? || link_sent_after_undelivered
  end

  # The link copied after the latest email failed: staff sent it themselves, so the page only
  # notes the failure.
  def link_sent_after_undelivered
    return unless latest_problem_email

    sends.take_while { _1 != latest_email_send }.find { _1.channel == "link" }
  end

  # Each revision's sends, newest first, for the Revisions list and the responses.
  def sends_by_revision = sends.includes(:email_message).group_by(&:revision)

  private

  def latest_email_send = sends.find { _1.channel == "email" }

  def latest_problem_email
    email = latest_email
    email if email&.problem? && awaiting_client?
  end
end
