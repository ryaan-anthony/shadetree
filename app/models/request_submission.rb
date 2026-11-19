# The public request form (CLI-03): what a prospective client fills in, and turning it into a
# service request for the right client. Either an email or a phone number is enough.
#
#   submission = RequestSubmission.new(business:, **params)
#   submission.save # => the ServiceRequest, or false with errors
#
# Matching is within the business only, on email first, then phone, among active clients. A
# match gets the request, linked to their property at that address if they have one, and
# nothing else: no typed contact details and no new property, since a stranger who knows
# someone's phone number mustn't be able to change that client's record. The request keeps
# what was typed (contacts and address) for staff to act on.
class RequestSubmission
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :phone, :string
  attribute :address_line1, :string
  attribute :address_line2, :string
  attribute :city, :string
  attribute :region, :string
  attribute :postal_code, :string
  attribute :description, :string
  attribute :timing, :string
  attribute :location, :string # CAT-07: a location's uid, from its own link or the client's choice
  attr_accessor :business, :service_ids, :photos

  validates :name, presence: { message: "Tell us your name." }, length: { maximum: 120 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "That email doesn't look right." }, length: { maximum: 254 }, allow_blank: true
  validates :address_line1, presence: { message: "Tell us where the work is." }, length: { maximum: 120 }
  validates :address_line2, :city, :region, length: { maximum: 120 }
  validates :postal_code, length: { maximum: 20 }
  validates :description, length: { maximum: 5_000 }
  validates :timing, inclusion: { in: ServiceRequest::TIMINGS }, allow_blank: true
  validate :email_or_phone
  validate :phone_is_a_phone_number
  validate :something_to_quote
  validate :photos_are_allowed
  validate { errors.add(:location, "Choose one of the locations listed.") if location.present? && chosen_location.nil? }

  def initialize(business:, **attributes)
    super(**attributes)
    self.business = business
    self.service_ids = Array(service_ids).compact_blank.map(&:to_s).first(50)
    self.photos = Array(photos).compact_blank
  end

  # The services offered on the form, in catalog order.
  def self.offered_services = CatalogItem.active.where(show_on_request_form: true).ordered

  def services = self.class.offered_services.where(uid: service_ids).to_a

  # CAT-07: the location the request is for; none chosen means the main location.
  def chosen_location = (@chosen_location ||= Location.active.find_by(uid: location.to_s) if location.present?)

  # The saved request, or false.
  def save
    return false unless valid?

    ServiceRequest.transaction do
      matched = matching_client
      client = matched || new_client
      property = matched ? existing_property(matched) : client.properties.first
      request = ServiceRequest.new(client:, property:, source: "form", location: chosen_location, description:, timing:, address: typed_address,
                                   services: services.map { { "catalog_item_id" => _1.id, "name" => _1.name } },
                                   contact_name: name, contact_email: email, contact_phone: phone, matched_existing_client: matched.present?)
      @cleaned_photos.each { request.photos.attach(_1) }
      request.save!
      request
    end
  end

  private

  def normalized_email = ClientContactMethod.normalize("email", email)
  def normalized_phone = ClientContactMethod.normalize("phone", phone)

  # Email first (more specific), then phone; the most recently active client if several.
  def matching_client
    by_email = Client.active.matching(emails: [ email ]).order(last_activity_at: :desc).first if email.present?
    by_email || (Client.active.matching(phones: [ phone ]).order(last_activity_at: :desc).first if phone.present?)
  end

  # Someone new: a client with what they typed, and their address as the billing property.
  def new_client
    contacts = [ ({ kind: "email", value: email } if email.present?), ({ kind: "phone", value: phone } if phone.present?) ].compact
    Client.create!(display_name: name, contact_methods_attributes: contacts,
                   properties_attributes: [ typed_address.merge("country" => business.country, "billing" => true) ])
  end

  # A matched client's property at this street address and postal code, if they have one.
  def existing_property(client)
    key = ->(line1, postal) { [ line1.to_s.squish.downcase, postal.to_s.delete(" ").downcase ] }
    wanted = key.(address_line1, postal_code)
    client.properties.find { key.(_1.address_line1, _1.postal_code) == wanted }
  end

  def typed_address = { "address_line1" => address_line1, "address_line2" => address_line2, "city" => city, "region" => region,
                        "postal_code" => postal_code }.transform_values { _1.to_s.squish.presence }.compact

  def email_or_phone
    errors.add(:email, "Add an email or a phone number so we can reply.") if email.blank? && phone.blank?
  end

  def phone_is_a_phone_number
    return if phone.blank?

    digits = phone.gsub(/\D/, "").length
    errors.add(:phone, "That phone number doesn't look right.") unless digits.between?(ClientContactMethod::MIN_PHONE_DIGITS, ClientContactMethod::MAX_PHONE_DIGITS)
  end

  def something_to_quote
    errors.add(:description, "Pick a service or tell us about the job.") if description.blank? && services.empty?
  end

  # Photos are re-encoded without their metadata (phone photos carry GPS), as on quotes. Once
  # per submission, however often it's validated.
  def photos_are_allowed
    return errors.add(:photos, "You can add up to #{ServiceRequest::MAX_PHOTOS} photos.") if photos.size > ServiceRequest::MAX_PHOTOS

    @photo_results ||= photos.map { [ _1, LogoUpload.clean_photo(_1, max_bytes: ServiceRequest::PHOTO_MAX_BYTES) ] }
    @photo_results.each do |file, result|
      errors.add(:photos, "#{file.try(:original_filename) || "A photo"} #{result.error}.") if result.error
    end
    @cleaned_photos = @photo_results.filter_map { _2.attachable unless _2.error }
  end
end
