# OPS-05: how support email is threaded. Outgoing replies carry the ticket's reference in the
# subject ("[#abc123]") and in the Message-ID, so an answer by email can be matched back to its
# ticket from either.
#
# SupportMail.receive(mail) takes an email sent to the support address (a Mail::Message) and:
# - from a member, answering a ticket of one of their businesses: adds their reply (reopening it);
# - from a member, about anything else: opens a ticket in the business they last used;
# - from anyone else: ignores it.
# NOT CONNECTED, ON PURPOSE: nothing calls receive yet, and it must stay that way until the
# spec's open question is settled. It trusts the From address, which anyone can forge. Before
# wiring it to any inbound email: (1) prove the sender, either the provider's verified DKIM/SPF
# result or a signed reply address per recipient (support+<token>@…) instead of From; (2) stop
# matching tickets by subject alone (headers or the signed address only); (3) rate limit per
# sender and per business, as the in-app form is.
module SupportMail
  Result = Data.define(:outcome, :ticket)
  UID = /[1-9A-HJ-NP-Za-km-z]{#{BusinessOwned::UID_LENGTH}}/o
  QUOTE_STARTS = [ /^On .+wrote:\s*$/, /^-{2,}\s*Original Message/i, /^From: .+$/, /^>/ ].freeze

  module_function

  def subject_for(ticket) = "Re: #{ticket.subject} [#{ticket.reference}]"

  def message_id_for(ticket, message) = "<ticket-#{ticket.uid}-#{message.id}-#{SecureRandom.hex(4)}@#{ApplicationMailer.sending_domain}>"

  def receive(mail)
    user = User.find_by(email: Array(mail.from).first.to_s.strip.downcase)
    return Result.new(outcome: :unknown_sender, ticket: nil) if user.nil? || user.deleted?

    body = reply_text(mail)
    return Result.new(outcome: :empty, ticket: nil) if body.blank?

    files = images(mail)
    ticket = ticket_for(mail)
    membership = ticket && user.business_users.active.find_by(business_id: ticket.business_id)
    if membership && Tenancy.with_business(ticket.business) { SupportTicket.visible_to(membership).exists?(ticket.id) }
      Tenancy.with_business(ticket.business) { ticket.reply_from_member!(user, body, files:, source: "email") }
      return Result.new(outcome: :replied, ticket:)
    end

    membership = membership_for(user) or return Result.new(outcome: :no_business, ticket: nil)
    ticket = Tenancy.with_business(membership.business) do
      SupportTicket.open!(opened_by: user, subject: mail.subject.to_s.sub(/\A(re|fwd?):\s*/i, "").presence&.first(150) || "Email to support",
                          category: "question", body:, files:, browser: "Email")
    end
    Result.new(outcome: ticket.persisted? ? :opened : :invalid, ticket:)
  end

  # The ticket named in the headers (our Message-ID) or the subject, in any business.
  def ticket_for(mail)
    ids = [ mail.in_reply_to, mail.references ].flatten.compact.join(" ")
    uid = ids[/ticket-(#{UID})-/o, 1] || mail.subject.to_s[/\[#(#{UID})\]/o, 1]
    uid && Tenancy.across_businesses(reason: "threading a support email (OPS-05)") { SupportTicket.includes(:business).find_by(uid:) }
  end

  # The business they last used, else their newest.
  def membership_for(user)
    memberships = user.business_users.active.joins(:business).merge(Business.active).includes(:business)
    memberships.find_by(business_id: user.last_business_id) || memberships.order(created_at: :desc).first
  end

  # What they wrote, without the quoted thread below it.
  def reply_text(mail)
    part = mail.multipart? ? (mail.text_part || mail.html_part) : mail
    text = part&.decoded.to_s
    text = ActionController::Base.helpers.strip_tags(text) if part&.mime_type == "text/html"
    lines = text.lines
    cut = lines.index { |line| QUOTE_STARTS.any? { line.match?(_1) } } || lines.size
    lines.first(cut).join.strip.first(20_000)
  end

  def images(mail)
    mail.attachments.select { _1.mime_type.to_s.start_with?("image/") }.first(SupportMessage::MAX_FILES).map do |attachment|
      { io: StringIO.new(attachment.decoded), filename: attachment.filename }
    end
  end
end
