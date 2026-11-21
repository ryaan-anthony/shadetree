# One outbound client-facing email (NTF-01): who it went to, what it was about, and what
# became of it as the SMTP server reported it (ADR 0017).
class EmailMessage < ApplicationRecord
  include BusinessOwned

  # bounced: the mail server refused the address; suppressed: not sent, the address is blocked.
  STATUSES = %w[queued sent bounced failed suppressed].freeze
  PROBLEMS = %w[bounced failed suppressed].freeze

  belongs_to :related, polymorphic: true, optional: true

  normalizes :to, with: ->(email) { email.to_s.strip.downcase }

  validates :kind, inclusion: { in: -> { EmailCatalog.kinds } }
  validates :to, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Client email a business can trigger in an hour (the platform's sending domain isn't a
  # relay). Staff sends are rate limited at the controller; email a client's action triggers
  # (an approval confirmation to an address they typed) checks this before queueing.
  CLIENT_EMAILS_PER_HOUR = 30
  def self.hourly_limit_reached? = where(created_at: 1.hour.ago..).count >= CLIENT_EMAILS_PER_HOUR
  scope :problems, -> { where(status: PROBLEMS) }

  def problem? = status.in?(PROBLEMS)

  # announce: the mail server refused it or it couldn't be sent (ClientMailDeliveryJob), so it's
  # put on the client's timeline and the team is told. Emails skipped before sending (the
  # document changed, a blocked address) are only marked.
  def mark!(status, at: Time.current, announce: status == "bounced", **attributes)
    stamp = { "sent" => :sent_at, "bounced" => :bounced_at, "failed" => :failed_at }[status]
    Tenancy.with_business(business) do
      transaction do
        update!(status:, **(stamp ? { stamp => at } : {}), **attributes)
        announce_undelivered(at) if announce && problem?
      end
    end
  end

  # When it went wrong, for the "not delivered" warnings.
  def problem_at = bounced_at || failed_at || updated_at

  # The mail server's reply code ("554 5.7.1"), kept for anyone checking with the provider.
  # Only the code is stored, never the server's text (ADR 0017).
  def reply_code = error.to_s[/\b[45]\d\d(?: \d\.\d{1,3}\.\d{1,3})?\b/]

  # Why it wasn't delivered, in plain words for staff (the error keeps the reply code).
  def problem_reason
    text = error.to_s
    case status
    when "suppressed" then "It wasn't sent: an earlier email to this address was refused, so the address is blocked."
    when "bounced"
      if text.include?("one of the addresses") then "The receiving mail server refused one of the addresses (the client's or a CC)."
      else "The receiving mail server says this address doesn't exist or can't take email."
      end
    else
      if text.include?("credentials rejected") then "Shadetree's mail server wouldn't take it. This is on our side; try again later."
      elsif text.include?("refused the email") then "The receiving mail server rejected the email."
      elsif text.include?("couldn't take the email") then "The mail server didn't take it, even after trying again for about four hours."
      else text.presence || "It couldn't be sent."
      end
    end
  end

  # Plain words for staff.
  def status_label
    { "queued" => "Sending", "sent" => "Sent", "bounced" => "Address refused", "failed" => "Couldn't send",
      "suppressed" => "Not sent: address blocked" }.fetch(status)
  end

  private

  # CLI-05: an email that didn't arrive shows on the client's timeline; NTF-02: the team is told,
  # so someone fixes the address and resends.
  def announce_undelivered(at)
    client = related.try(:client)
    ClientEvent.record!(client, :email_bounced, subject: self, at:) if client
    NotificationType.deliver("email_not_delivered", business:, subject: related || self, title: "An email#{" to #{client.display_name}" if client} wasn't delivered",
                             body: [ document_label, problem_reason ].compact.join(": "), path: staff_path(client))
  end

  def document_label
    case related
    when Quote then "Quote #{related.number}"
    when Invoice then "Invoice #{related.number}"
    end
  end

  def staff_path(client)
    routes = Rails.application.routes.url_helpers
    case related
    when Quote then routes.admin_quote_path(related)
    when Invoice then routes.admin_invoice_path(related)
    else client ? routes.admin_client_path(client) : routes.admin_root_path
    end
  end
end
