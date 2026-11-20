# OPS-05: email to support (support@ or a member's signed support+<token>@ reply address),
# threaded into tickets by SupportMail with what the Email Worker vouched for. Whatever happens,
# only the outcome and ids are logged, never an address, subject or body.
class SupportMailbox < ApplicationMailbox
  def process
    result = SupportMail.receive(mail, envelope_to: inbound_email.envelope_to, envelope_from: inbound_email.envelope_from,
                                       auth_results: inbound_email.auth_results)
    Observability.log(:info, "support_mail.received", inbound_email_id: inbound_email.id, outcome: result.outcome.to_s, ticket: result.ticket&.uid)
  end
end
