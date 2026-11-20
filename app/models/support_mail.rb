# OPS-05: how support email is threaded. Outgoing replies carry the ticket's reference in the
# subject ("[#abc123]") and in the Message-ID, so an answer by email can be matched back to its
# ticket from either.
module SupportMail
  module_function

  def subject_for(ticket) = "Re: #{ticket.subject} [#{ticket.reference}]"

  def message_id_for(ticket, message) = "<ticket-#{ticket.uid}-#{message.id}-#{SecureRandom.hex(4)}@#{ApplicationMailer.sending_domain}>"
end
