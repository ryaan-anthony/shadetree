# One time an invoice went to its client (PAY-02): by email or as a link staff copied to send
# themselves, as quotes record theirs (QTE-04). The first send marks the invoice sent.
class InvoiceSend < ApplicationRecord
  include BusinessOwned

  CHANNELS = %w[email link].freeze

  belongs_to_business_record :invoice
  belongs_to :user, optional: true
  belongs_to :email_message, optional: true

  validates :channel, inclusion: { in: CHANNELS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def channel_label = channel == "email" ? "Emailed to #{recipient}" : "Link copied"
end
