# OPS-05: email to support (support@ or a member's signed support+<token>@ reply address).
# Threading into tickets (SupportMail) is wired in part 2; until then a message is only stored,
# then incinerated after 14 days.
class SupportMailbox < ApplicationMailbox
  def process
    Observability.log(:info, "support_mail.received", inbound_email_id: inbound_email.id, outcome: "stored")
  end
end
