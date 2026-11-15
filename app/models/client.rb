# Someone a business works for (CLI-01). Clients never sign in (plan 04, D1): they're records
# the business keeps, reached through client links (PLT-12).
class Client < ApplicationRecord
  include BusinessOwned

  MAX_TAGS = 20
  # Associations that make a client undeletable (archive instead). Later specs add theirs:
  # requests (CLI-04), quotes (QTE-01), jobs (JOB-01), invoices (INV-01).
  DOCUMENT_ASSOCIATIONS = [].freeze

  has_many :contact_methods, -> { order(:position, :id) }, class_name: "ClientContactMethod",
           inverse_of: :client, dependent: :delete_all
  has_many :properties, -> { order(billing: :desc, position: :asc, id: :asc) }, inverse_of: :client, dependent: :delete_all

  accepts_nested_attributes_for :contact_methods, allow_destroy: true,
                                reject_if: ->(attributes) { attributes["id"].blank? && attributes["value"].blank? }
  accepts_nested_attributes_for :properties, allow_destroy: true,
                                reject_if: ->(attributes) { attributes["id"].blank? && Property::ADDRESS_FIELDS.all? { attributes[_1].blank? } }

  normalizes :display_name, :company_name, with: ->(value) { value.to_s.squish.presence }
  normalizes :tags, with: ->(tags) { Array(tags).flat_map { _1.to_s.split(",") }.map { _1.squish.downcase }.compact_blank.uniq }

  validates :display_name, presence: true, length: { maximum: 120 }
  validates :company_name, length: { maximum: 120 }
  validates :notes, length: { maximum: 5_000 }
  validate :has_a_contact_method
  validate :tags_are_short
  validate :one_billing_property

  # Ticking "billing" on one property moves it there: the others are cleared, in memory before
  # validation and in the database before the properties save (a unique index allows one).
  before_validation :move_billing_to_newly_chosen_property
  before_save :clear_other_billing_properties

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :alphabetical, -> { order(Arel.sql("lower(clients.display_name)"), :id) }

  # Clients with any of these emails or phones, for duplicate suggestions (R4).
  def self.matching(emails: [], phones: [])
    emails = Array(emails).filter_map { ClientContactMethod.normalize("email", _1) }
    phones = Array(phones).filter_map { ClientContactMethod.normalize("phone", _1) }.select { _1.length >= ClientContactMethod::MIN_PHONE_DIGITS }
    return none if emails.empty? && phones.empty?

    methods = ClientContactMethod.where(kind: "email", normalized: emails).or(ClientContactMethod.where(kind: "phone", normalized: phones))
    where(id: methods.select(:client_id))
  end

  def archived? = archived_at.present?
  def archive! = update!(archived_at: Time.current)
  def restore! = update!(archived_at: nil)

  def emails = contact_methods.select(&:email?)
  def phones = contact_methods.select(&:phone?)
  def primary_email = emails.first
  def primary_phone = phones.first
  def primary_contact = primary_phone || primary_email
  def billing_property = properties.find(&:billing)
  def primary_property = billing_property || properties.first

  def documents? = DOCUMENT_ASSOCIATIONS.any? { public_send(_1).exists? }
  def deletable? = !documents?

  # Tags as typed in the form: "commercial, weekly".
  def tag_list = tags.join(", ")
  def tag_list=(value)
    self.tags = value.to_s.split(",")
  end

  # Contact rows emptied in the form are removed rather than failing validation.
  def contact_methods_attributes=(attributes)
    rows = attributes.respond_to?(:each_pair) ? attributes.to_h.values : Array(attributes)
    super(rows.map { |row| (row = row.to_h.stringify_keys)["id"].present? && row["value"].blank? ? row.merge("_destroy" => "1") : row })
  end

  # What the inline picker (and CLI-02's search) hands back to the flow that asked.
  def as_picker_json
    { uid:, name: display_name, company: company_name, contact: primary_contact&.value,
      property: primary_property&.one_line }
  end

  private

  def kept(collection) = collection.reject(&:marked_for_destruction?)

  def has_a_contact_method
    errors.add(:base, "Add an email or a phone number so you can reach this client.") if kept(contact_methods).empty?
  end

  def tags_are_short
    errors.add(:tags, "can have at most #{MAX_TAGS}") if tags.size > MAX_TAGS
    errors.add(:tags, "must each be 30 characters or fewer") if tags.any? { _1.length > 30 }
  end

  def one_billing_property
    errors.add(:base, "Only one property can be the billing address.") if kept(properties).count(&:billing) > 1
  end

  def newly_chosen_billing_property
    chosen = kept(properties).select { _1.billing && (_1.new_record? || _1.billing_changed?) }
    chosen.first if chosen.one?
  end

  def move_billing_to_newly_chosen_property
    chosen = newly_chosen_billing_property or return
    properties.each { _1.billing = false unless _1.equal?(chosen) }
  end

  def clear_other_billing_properties
    chosen = newly_chosen_billing_property
    return unless chosen && persisted?

    Property.where(client_id: id, billing: true).where.not(id: chosen.id).update_all(billing: false)
  end
end
