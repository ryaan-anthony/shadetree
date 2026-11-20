# OPS-05: email to support (support@ or a member's signed support+<token>@ reply address),
# threaded into tickets by SupportMail with what the Email Worker vouched for. Whatever happens,
# only the outcome and ids are logged, never an address, subject or body.
class SupportMailbox < ApplicationMailbox
  def process
    result = if plain_copy_of_a_reply?
      SupportMail::Result.new(outcome: :duplicate, ticket: nil)
    else
      SupportMail.receive(mail, envelope_to: inbound_email.envelope_to, envelope_from: inbound_email.envelope_from,
                                auth_results: inbound_email.auth_results)
    end
    Observability.log(:info, "support_mail.received", inbound_email_id: inbound_email.id, outcome: result.outcome.to_s, ticket: result.ticket&.uid)
  end

  private

  # A reply to support+<token>@ that also Cc'd support@ arrives twice; the plain copy would open
  # a second ticket, so it's dropped. (The Message-ID only ever drops a copy, never threads one.)
  def plain_copy_of_a_reply?
    return false if inbound_email.envelope_to.to_s.include?("+")

    (Array(mail.to) + Array(mail.cc)).any? { _1.to_s.include?("+") && InboundEmailIngress.support_recipient?(_1) } ||
      ActionMailbox::InboundEmail.where(message_id: inbound_email.message_id).where.not(id: inbound_email.id).where("envelope_to LIKE ?", "%+%").exists?
  end
end
