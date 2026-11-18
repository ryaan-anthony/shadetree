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
  belongs_to :created_by, class_name: "User", optional: true
  has_many :views, class_name: "ServiceRequestView", dependent: :delete_all
  has_many :notes, -> { order(:created_at, :id) }, class_name: "ServiceRequestNote", dependent: :delete_all
  has_many :quotes, -> { order(:created_at) }, dependent: :nullify
  has_many_attached :photos do |attachable|
    attachable.variant :web, resize_to_limit: [ 640, 640 ], preprocessed: true
  end

  normalizes :description, with: ->(value) { value.to_s.strip.presence }
  normalizes :timing, :contact_name, :contact_phone, with: ->(value) { value.to_s.squish.presence }
  normalizes :contact_email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :description, presence: { message: "Say what they need." }, if: -> { source != "form" && services.empty? }
  validates :source, inclusion: { in: SOURCES }
  validates :description, length: { maximum: 5_000 }
  validates :timing, length: { maximum: 120 }
  validates :contact_name, length: { maximum: 120 }
  validate { errors.add(:photos, "can be at most #{MAX_PHOTOS}") if photos.size > MAX_PHOTOS }

  after_create_commit :notify, if: -> { source == "form" }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  LABELS = { "new" => "New", "in_progress" => "In progress", "quoted" => "Quoted", "archived" => "Archived" }.freeze
  SOURCE_LABELS = { "form" => "Request form", "phone" => "Phone", "email" => "Email", "walk_in" => "In person", "other" => "Other" }.freeze
  def status_label = LABELS.fetch(status)
  def source_label = SOURCE_LABELS.fetch(source)

  # A short reference for lists and quotes: R-<id> would leak volume, so the uid's start (case
  # kept: uids are case-sensitive).
  def reference = "R-#{uid.first(8)}"

  # CLI-04: opening a request records that this member has seen it.
  def viewed_by!(user)
    ServiceRequestView.upsert({ business_id:, service_request_id: id, user_id: user.id, viewed_at: Time.current },
                              unique_by: %i[service_request_id user_id], update_only: %i[viewed_at])
  end

  # Staff change the status by hand, except to Quoted: that happens when a quote is made.
  MANUAL_STATUSES = %w[new in_progress archived].freeze
  def move_to!(status)
    raise ArgumentError, "Can't set status #{status.inspect} by hand" unless MANUAL_STATUSES.include?(status.to_s)

    update!(status:)
  end

  # CLI-04: a draft quote from this request: its client and property (a property for the
  # typed address if the request has none, now that a staff member has checked it), its
  # services as lines with today's catalog prices, and its photos.
  def create_quote!(by:)
    transaction do
      lock!
      property = self.property || property_matching_address
      quote = Quote.start(client:, property:, created_by: by)
      items = CatalogItem.where(id: services.map { _1["catalog_item_id"] }).index_by(&:id)
      quote.sync_line_items(services.each_with_index.map do |service, index|
        item = items[service["catalog_item_id"]]
        base = { "key" => "request-#{index}", "name" => service["name"], "quantity" => "1" }
        item ? base.merge("catalog_item" => item.uid, "name" => item.name, "description" => item.description, "unit" => item.unit_label,
                          "unit_price" => item.unit_price&.to_s || "0", "taxable" => item.taxable ? "1" : "0") : base
      end)
      photos.each { quote.attachments.attach(_1.blob) }
      quote.service_request = self
      quote.save!
      update!(status: "quoted", property: property || self.property)
      quote
    end
  end

  def service_names = services.map { _1["name"] }

  # The service address as typed, one line ("12 Maple St, Austin, 06804").
  def address_line = address.values_at(*%w[address_line1 address_line2 city region postal_code]).compact.join(", ").presence

  # Whether the acknowledgment email was queued (set when the request is created).
  def acknowledgment_queued? = @acknowledgment_queued == true

  # A quote made from this request was deleted: with none left, it's back to In progress.
  def quote_removed!
    update!(status: "in_progress") if status == "quoted" && !quotes.exists? # exists? always asks the database
  end

  # The client's property at the typed street address and postal code, if they have one. A new
  # address isn't added to the client here: the builder shows it, for staff to add if it's real.
  def property_matching_address
    return if address["address_line1"].blank?

    key = ->(line1, postal) { [ line1.to_s.squish.downcase, postal.to_s.delete(" ").downcase ] }
    wanted = key.(address["address_line1"], address["postal_code"])
    client.properties.find { key.(_1.address_line1, _1.postal_code) == wanted }
  end

  private

  # The team hears about it. The person who sent it gets an acknowledgment if they gave an
  # email, the business's owner has confirmed their account (so a throwaway sign-up can't use
  # the platform's address to send its name to anyone, as AGENTS.md requires of client email),
  # and the business is under its hourly client email limit.
  def notify
    NewRequestMailer.deliver_later_for(self)
    return if contact_email.blank? || !business.owner&.can_send_to_clients? || EmailMessage.hourly_limit_reached?

    RequestMailer.send_later(:received, business:, to: contact_email, kind: "request_received", related: self, request_id: id)
    @acknowledgment_queued = true
  end
end
