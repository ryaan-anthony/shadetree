# One time a quote went to its client (QTE-04): by email or as a link staff copied to send
# themselves. The first send marks the quote sent; resends are recorded the same way.
class QuoteSend < ApplicationRecord
  include BusinessOwned

  CHANNELS = %w[email link].freeze

  belongs_to_business_record :quote
  belongs_to :user, optional: true
  belongs_to :email_message, optional: true

  validates :channel, inclusion: { in: CHANNELS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def channel_label = channel == "email" ? "Emailed to #{recipient}" : "Link copied"
end
