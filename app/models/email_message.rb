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

  # #289: emails about one client's own records (their quotes, invoices, payments, jobs, visits
  # and requests), not every email to an address: two clients can share one (a couple, a test
  # address), and each should only see their own.
  scope :about_client, ->(client) {
    invoices = Invoice.where(client:).select(:id)
    where(related_type: "Quote", related_id: Quote.where(client:).select(:id))
      .or(where(related_type: "Invoice", related_id: invoices))
      .or(where(related_type: "Payment", related_id: Payment.where(invoice_id: invoices).select(:id)))
      .or(where(related_type: "Job", related_id: Job.where(client:).select(:id)))
      .or(where(related_type: "ServiceRequest", related_id: ServiceRequest.where(client:).select(:id)))
      .or(where(related_type: "Visit", related_id: Visit.where(job_id: Job.where(client:).select(:id)).select(:id))) # automations' emails
  }

  # Client email a business can trigger in an hour (the platform's sending domain isn't a
  # relay). Staff sends are rate limited at the controller; email a client's action triggers
  # (an approval confirmation to an address they typed) checks this before queueing.
  CLIENT_EMAILS_PER_HOUR = 30
  def self.hourly_limit_reached? = where(created_at: 1.hour.ago..).count >= CLIENT_EMAILS_PER_HOUR
  scope :problems, -> { where(status: PROBLEMS) }

  # Reported to operators when a client email fails on Shadetree's side (QA #274).
  class UndeliveredOnOurSide < StandardError; end

  def problem? = status.in?(PROBLEMS)

  # NTF-05: the CCs the quote or invoice send copied this email to, lowercased, in order.
  def cc_addresses
    send = QuoteSend.find_by(email_message_id: id) || InvoiceSend.find_by(email_message_id: id)
    send&.cc.to_s.split(/[,;\s]+/).compact_blank.map(&:downcase)
  end

  # announce: the mail server refused it or it couldn't be sent (ClientMailDeliveryJob), so it's
  # announced (see #announce_undelivered), once, when its status changes. Emails skipped before
  # sending (the document changed, a blocked address) are only marked.
  def mark!(status, at: Time.current, announce: status == "bounced", **attributes)
    stamp = { "sent" => :sent_at, "bounced" => :bounced_at, "failed" => :failed_at }[status]
    Tenancy.with_business(business) do
      transaction do
        update!(status:, **(stamp ? { stamp => at } : {}), **attributes)
        announce_undelivered(at) if announce && problem? && saved_change_to_status?
      end
    end
  end

  # The failure is Shadetree's, not the client's address: our mail server rejected our
  # credentials, or there's no reply from a receiving server at all (a relay outage past the
  # retries, an unexpected error).
  def our_side? = status == "failed" && (error.to_s.include?("credentials rejected") || reply_code.nil?)

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
      if our_side? && (text.include?("credentials rejected") || text.start_with?("The mail server", "Something went wrong"))
        "Something went wrong on Shadetree's side, not with the address. We've been told; try again later."
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
  # so someone fixes the address and resends. Not for a test email (staff's own address), nor
  # for an old send that a later one has replaced (the document's page has nothing to warn
  # about). A failure on Shadetree's side goes to operators, once, instead of every team.
  def announce_undelivered(at)
    return if kind == "test_message" || superseded?

    client = related.is_a?(Payment) ? related.invoice.client : related.try(:client)
    ClientEvent.record!(client, :email_bounced, subject: self, at:) if client
    if our_side?
      Rails.error.report(UndeliveredOnOurSide.new("client email failed on our side: #{error}"), handled: true,
                         context: { record_type: "EmailMessage", record_id: id, business_id:, kind: }) # "email" keys are filtered
    else
      NotificationType.deliver("email_not_delivered", business:, subject: notification_subject, title: "An email#{" to #{client.display_name}" if client} wasn't delivered",
                               body: "#{about}: #{problem_reason}", path: staff_path(client))
    end
  end

  # A send of a quote or invoice whose document has been sent by email again since.
  def superseded?
    sends = related.try(:sends) or return false
    emailed = sends.unscope(:order).where(channel: "email")
    emailed.exists?(email_message_id: id) && emailed.order(created_at: :desc, id: :desc).pick(:email_message_id) != id
  end

  # Receipts are about a payment; the notice is filed under its invoice (so erasing the client
  # scrubs it, INS-02).
  def notification_subject = related.is_a?(Payment) ? related.invoice : (related || self)

  # What the email was: the quote or invoice itself when that's what was sent, otherwise its
  # kind ("Automated message for Quote Q-0001", "Payment receipt for Invoice INV-0001").
  def about
    return document_label if kind.in?(%w[quote_sent invoice_sent]) && document_label

    [ EmailCatalog.find(kind).name, document_label ].compact.join(" for ")
  end

  def document_label
    case related
    when Quote then "Quote #{related.number}"
    when Invoice then "Invoice #{related.number}"
    when Payment then "Invoice #{related.invoice.number}"
    end
  end

  def staff_path(client)
    routes = Rails.application.routes.url_helpers
    case related
    when Quote then routes.admin_quote_path(related)
    when Invoice then routes.admin_invoice_path(related)
    when Payment then routes.admin_invoice_path(related.invoice)
    else client ? routes.admin_client_path(client) : routes.admin_root_path
    end
  end
end
