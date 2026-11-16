# The public request form (CLI-03): what a prospective client fills in, and turning it into a
# service request for the right client. Either an email or a phone number is enough.
#
#   submission = RequestSubmission.new(business:, **params)
#   submission.save # => the ServiceRequest, or false with errors
#
# Matching is within the business only, on email first, then phone, among active clients. A
# match gets the request (and a new property if the address is new to them) but none of the
# typed contact details: a stranger who knows someone's phone number mustn't be able to
# change where that client's quotes go. Staff see what was typed on the request.
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

  def initialize(business:, **attributes)
    super(**attributes)
    self.business = business
    self.service_ids = Array(service_ids).compact_blank.map(&:to_s).first(50)
    self.photos = Array(photos).compact_blank
  end

  # The services offered on the form, in catalog order.
  def self.offered_services = CatalogItem.active.where(show_on_request_form: true).ordered

  def services = self.class.offered_services.where(uid: service_ids).to_a

  def save
    return false unless valid?

    ServiceRequest.transaction do
      matched = matching_client
      client = matched || new_client
      property = property_for(client)
      request = ServiceRequest.new(client:, property:, source: "form", description:, timing:,
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
    by_email = Client.active.matching(emails: [ email ]).order(updated_at: :desc).first if email.present?
    by_email || (Client.active.matching(phones: [ phone ]).order(updated_at: :desc).first if phone.present?)
  end

  def new_client
    contacts = [ ({ kind: "email", value: email } if email.present?), ({ kind: "phone", value: phone } if phone.present?) ].compact
    Client.create!(display_name: name, contact_methods_attributes: contacts)
  end

  # The client's property at this street address and postal code, or a new one (the billing
  # address if it's their first).
  def property_for(client)
    key = ->(line1, postal) { [ line1.to_s.squish.downcase, postal.to_s.delete(" ").downcase ] }
    wanted = key.(address_line1, postal_code)
    client.properties.find { key.(_1.address_line1, _1.postal_code) == wanted } ||
      client.properties.create!(address_line1:, address_line2:, city:, region:, postal_code:, country: business.country,
                                billing: client.properties.none?)
  end

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

  # Photos are re-encoded without their metadata (phone photos carry GPS), as on quotes.
  def photos_are_allowed
    @cleaned_photos = []
    return if photos.empty?
    return errors.add(:photos, "You can add up to #{ServiceRequest::MAX_PHOTOS} photos.") if photos.size > ServiceRequest::MAX_PHOTOS

    photos.each do |file|
      result = LogoUpload.clean_photo(file, max_bytes: ServiceRequest::PHOTO_MAX_BYTES)
      next errors.add(:photos, "#{file.try(:original_filename) || "A photo"} #{result.error}.") if result.error

      @cleaned_photos << result.attachable
    end
  end
end
