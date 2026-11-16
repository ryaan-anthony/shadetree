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
  scope :problems, -> { where(status: PROBLEMS) }

  def problem? = status.in?(PROBLEMS)

  def mark!(status, at: Time.current, **attributes)
    stamp = { "sent" => :sent_at, "bounced" => :bounced_at, "failed" => :failed_at }[status]
    update!(status:, **(stamp ? { stamp => at } : {}), **attributes)
  end

  # Plain words for staff.
  def status_label
    { "queued" => "Sending", "sent" => "Sent", "bounced" => "Address refused", "failed" => "Couldn't send",
      "suppressed" => "Not sent: address blocked" }.fetch(status)
  end
end
