# OPS-05: email to the support address, as Cloudflare Email Routing and the Email Worker deliver
# it (ADR 0021; SupportMailbox passes the envelope recipient and Cloudflare's own
# Authentication-Results). The From header alone proves nothing, so:
#
# - A reply threads into a ticket only through the member's signed reply address
#   (support+<token>@…, from reply_address, used as Reply-To on our emails), only when From is
#   that token's user, Cloudflare saw DMARC pass or an SPF/DKIM pass aligned with From, and the
#   user may still see the ticket (an active member; SupportTicket.visible_to).
# - Other email opens a ticket only with DMARC pass and a From that's an active member.
# - Subject lines and Message-IDs are never trusted to pick a ticket.
# - Automatic mail (bounces, auto-replies, lists) and everything that fails is dropped quietly:
#   no reply is ever sent, so there are no loops. The outcome is logged by SupportMailbox.
# - Each sender and business can add only so much an hour, as in the app.
module SupportMail
  Result = Data.define(:outcome, :ticket)
  QUOTE_STARTS = [ /^On .+wrote:\s*$/, /^-{2,}\s*Original Message/i, /^From: .+$/, /^>/ ].freeze
  TOKEN = /\A([0-9a-z]{1,13})-([0-9a-z]{1,13})-([0-9a-f]{20})\z/
  AUTOMATED_SENDERS = /\A(mailer-daemon|postmaster|no-?reply|do-?not-?reply)\b/i
  BULK_PRECEDENCE = %w[bulk junk list auto_reply].freeze

  module_function

  def subject_for(ticket) = "Re: #{ticket.subject} [#{ticket.reference}]"

  def message_id_for(ticket, message) = "<ticket-#{ticket.uid}-#{message.id}-#{SecureRandom.hex(4)}@#{ApplicationMailer.sending_domain}>"

  # support+<ticket>-<user>-<mac>@getshadetree.com: lowercase, well under the 64-character limit
  # for the part before the @, and no expiry (leaving the business ends it).
  def reply_address(ticket, user)
    local, domain = ContactMailer.support_address.split("@", 2)
    ids = "#{ticket.id.to_s(36)}-#{user.id.to_s(36)}"
    "#{local}+#{ids}-#{token_mac(ids)}@#{domain}"
  end

  def receive(mail, envelope_to:, envelope_from:, auth_results:)
    return result(:automated) if automated?(mail, envelope_from)

    froms = Array(mail.from)
    from = froms.first.to_s.strip.downcase
    return result(:unknown_sender) unless froms.one? && from.include?("@")

    auth = InboundEmailAuth.parse(auth_results)
    token = envelope_to.to_s.downcase[/\A<?[^+@]+\+([^@]+)@/, 1]
    token ? reply(mail, from, auth, token) : open_ticket(mail, from, auth)
  end

  def reply(mail, from, auth, token)
    ticket, user = from_token(token)
    return result(:bad_token) unless ticket && user && !user.deleted?
    return result(:forged_sender) unless user.email.to_s.downcase == from
    return result(:unauthenticated) unless auth.aligned_pass?(domain_of(from))

    membership = active_membership(user, ticket.business)
    visible = membership && Tenancy.with_business(ticket.business) { SupportTicket.visible_to(membership).exists?(ticket.id) }
    return result(:not_member) unless visible
    return result(:rate_limited) if over_limit?(user, ticket.business)

    body = reply_text(mail)
    return result(:empty) if body.blank?

    message = Tenancy.with_business(ticket.business) { ticket.reply_from_member!(user, body, files: images(mail, user), source: "email") }
    Result.new(outcome: message.persisted? ? :replied : :invalid, ticket:)
  end

  def open_ticket(mail, from, auth)
    return result(:unauthenticated) unless auth.dmarc_pass?(domain_of(from))

    user = User.find_by(email: from)
    membership = user && !user.deleted? && membership_for(user)
    return result(:not_member) unless membership
    return result(:rate_limited) if over_limit?(user, membership.business)

    body = reply_text(mail)
    return result(:empty) if body.blank?

    ticket = Tenancy.with_business(membership.business) do
      SupportTicket.open!(opened_by: user, subject: mail.subject.to_s.sub(/\A(re|fwd?):\s*/i, "").presence&.first(150) || "Email to support",
                          category: "question", body:, files: images(mail, user), browser: "Email")
    end
    Result.new(outcome: ticket.persisted? ? :opened : :invalid, ticket:)
  end

  # Bounces (empty envelope sender), auto-replies, mailing lists and delivery reports.
  def automated?(mail, envelope_from)
    return true if envelope_from.to_s.strip.delete("<>").empty?
    return true if mail.header["Return-Path"] && mail.header["Return-Path"].to_s.strip.delete("<>").empty?

    auto_submitted = mail.header["Auto-Submitted"].to_s.strip.downcase
    auto_submitted.present? && auto_submitted != "no" ||
      BULK_PRECEDENCE.include?(mail.header["Precedence"].to_s.strip.downcase) ||
      %w[X-Autoreply X-Autorespond List-Id List-Unsubscribe].any? { mail.header[_1] } ||
      mail.mime_type.to_s.downcase == "multipart/report" ||
      Array(mail.from).any? { AUTOMATED_SENDERS.match?(_1.to_s) }
  end

  def from_token(token)
    match = TOKEN.match(token) or return
    ids = "#{match[1]}-#{match[2]}"
    return unless ActiveSupport::SecurityUtils.secure_compare(match[3], token_mac(ids))

    ticket = Tenancy.across_businesses(reason: "threading a support email by its signed reply address (OPS-05)") do
      SupportTicket.includes(:business).find_by(id: match[1].to_i(36))
    end
    [ ticket, User.find_by(id: match[2].to_i(36)) ]
  end

  def token_mac(ids) = OpenSSL::HMAC.hexdigest("SHA256", token_key, "support-reply:#{ids}").first(20)

  def token_key = Rails.application.key_generator.generate_key("support-reply-address/v1", 32)

  def active_membership(user, business)
    business.active? && user.business_users.active.find_by(business_id: business.id)
  end

  # The business they last used, else their newest.
  def membership_for(user)
    memberships = user.business_users.active.joins(:business).merge(Business.active).includes(:business)
    memberships.find_by(business_id: user.last_business_id) || memberships.order(created_at: :desc).first
  end

  # The same limits as the in-app form, counted only for mail that proved its sender, so forged
  # mail can't use up a member's allowance.
  def over_limit?(user, business)
    [ [ "user:#{user.id}", Admin::SupportTicketsController::PER_USER_PER_HOUR ],
      [ "business:#{business.id}", Admin::SupportTicketsController::PER_BUSINESS_PER_HOUR ] ].map do |key, limit|
      Rails.cache.increment("support-mail:#{key}", 1, expires_in: 1.hour).to_i > limit
    end.any?
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

  # Screenshots, as in the app: only from a confirmed account.
  def images(mail, user)
    return [] unless user.confirmed?

    mail.attachments.select { _1.mime_type.to_s.start_with?("image/") }.first(SupportMessage::MAX_FILES).map do |attachment|
      { io: StringIO.new(attachment.decoded), filename: attachment.filename }
    end
  end

  def domain_of(address) = address.to_s.split("@").last.to_s.downcase

  def result(outcome) = Result.new(outcome:, ticket: nil)
end
