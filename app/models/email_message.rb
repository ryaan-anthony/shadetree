# One outbound client-facing email (NTF-01): who it went to, what it was about, and what
# became of it, updated from the provider's delivery events.
class EmailMessage < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[queued sent delivered bounced complained failed suppressed].freeze
  # Outcomes that end the story: a late "sent" or "delivered" doesn't overwrite them.
  FINAL = %w[bounced complained failed suppressed].freeze

  belongs_to :related, polymorphic: true, optional: true

  normalizes :to, with: ->(email) { email.to_s.strip.downcase }

  validates :kind, inclusion: { in: -> { EmailCatalog.kinds } }
  validates :to, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :problems, -> { where(status: %w[bounced complained failed suppressed]) }

  def problem? = status.in?(%w[bounced complained failed suppressed])

  def mark!(status, at: Time.current, **attributes)
    return if FINAL.include?(self.status) && status.in?(%w[sent delivered])

    stamp = { "sent" => :sent_at, "delivered" => :delivered_at, "bounced" => :bounced_at,
              "complained" => :complained_at, "failed" => :failed_at }[status]
    update!(status:, **(stamp ? { stamp => at } : {}), **attributes)
  end

  # Plain words for staff.
  def status_label
    { "queued" => "Sending", "sent" => "Sent", "delivered" => "Delivered", "bounced" => "Bounced",
      "complained" => "Marked as spam", "failed" => "Couldn't send", "suppressed" => "Not sent: address blocked" }.fetch(status)
  end
end
