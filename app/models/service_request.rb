# A request for work (CLI-03): from the public request form, or entered by staff for a phone
# call or walk-in (CLI-04). It belongs to a client and, usually, one of their properties. What
# the person typed is kept on the request as submitted; matching them to an existing client
# never changes that client's details.
class ServiceRequest < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[new in_progress quoted archived].freeze
  SOURCES = %w[form phone email walk_in other].freeze
  MAX_PHOTOS = 5 # until plans set their own (BIL-01)
  PHOTO_MAX_BYTES = 10.megabytes
  # The form's timing choices; staff-entered requests may say anything.
  TIMINGS = [ "As soon as possible", "In the next few weeks", "I'm flexible" ].freeze

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  has_many_attached :photos do |attachable|
    attachable.variant :web, resize_to_limit: [ 640, 640 ], preprocessed: true
  end

  normalizes :description, with: ->(value) { value.to_s.strip.presence }
  normalizes :timing, :contact_name, :contact_phone, with: ->(value) { value.to_s.squish.presence }
  normalizes :contact_email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :description, length: { maximum: 5_000 }
  validates :timing, length: { maximum: 120 }
  validates :contact_name, length: { maximum: 120 }
  validate { errors.add(:photos, "can be at most #{MAX_PHOTOS}") if photos.size > MAX_PHOTOS }

  after_create_commit :notify, if: -> { source == "form" }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def service_names = services.map { _1["name"] }

  private

  # The team hears about it; the person who sent it gets an acknowledgment if they gave an
  # email (counted toward the business's hourly client email limit, like any client email a
  # stranger can trigger).
  def notify
    NewRequestMailer.deliver_later_for(self)
    return if contact_email.blank? || EmailMessage.hourly_limit_reached?

    RequestMailer.send_later(:received, business:, to: contact_email, kind: "request_received", related: self, request_id: id)
  end
end
