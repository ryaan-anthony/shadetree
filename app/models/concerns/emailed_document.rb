# A quote (QTE-04) or invoice (PAY-02) that goes to its client by email, and what became of
# that email. Only the latest email counts: a later send that went through settles an earlier
# problem. The document's status stays as it is (a quote stays "Sent"): the client's link
# still works, so the team is warned and resends instead (QA #274, owner decision 2026-11-21).
module EmailedDocument
  extend ActiveSupport::Concern

  def latest_email = sends.find { _1.channel == "email" }&.email_message

  # The email to warn about: the latest one didn't arrive, and the client hasn't answered or
  # paid yet (after that, it's history in the sends list).
  def undelivered_email
    email = latest_email
    email if email&.problem? && awaiting_client?
  end
end
