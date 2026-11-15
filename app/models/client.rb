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
  accepts_nested_attributes_for :properties, allow_destroy: true, reject_if: :untouched_new_property?

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

  before_save { self.last_activity_at = Time.current if new_record? || changed? || last_activity_at.nil? }
  # Contact methods and properties save after the client, so the digest is rebuilt once
  # everything is committed (children refresh it too when they change on their own).
  after_commit :refresh_search_text!, on: %i[create update]

  SORTS = { "name" => "Name", "recent" => "Recently added", "activity" => "Recent activity" }.freeze
  MAX_SEARCH_TERMS = 8

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :alphabetical, -> { order(Arel.sql("lower(clients.display_name)"), :id) }
  scope :sorted, ->(sort) {
    case sort
    when "recent" then order(created_at: :desc, id: :desc)
    when "activity" then order(last_activity_at: :desc, id: :desc)
    else alphabetical
    end
  }
  scope :tagged, ->(tag) { tag.present? ? where("clients.tags @> ARRAY[?]::varchar[]", tag.to_s.downcase) : all }

  # Clients matching every word of `query` anywhere in their name, company, email, phone or
  # address (CLI-02). Phone-like words ("(555)", "010-01") match on digits, so formatting
  # doesn't matter. Uses the trigram index on search_text.
  def self.search(query)
    query.to_s.downcase.split.first(MAX_SEARCH_TERMS).reduce(all) do |scope, term|
      digits = term.gsub(/\D/, "")
      term = digits if term.match?(/\A[\d()+.\-]+\z/) && digits.length >= 3
      scope.where("clients.search_text LIKE ?", "%#{sanitize_sql_like(term)}%")
    end
  end

  # Tags in use, for the filter.
  def self.tag_options(limit: 200)
    unscope(:order).distinct.order(:tag).limit(limit).pluck(Arel.sql("unnest(clients.tags) AS tag"))
  end

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

  # Called by later specs (quotes, jobs, invoices) when something happens for this client.
  def touch_activity!(at = Time.current) = update_column(:last_activity_at, at)

  # Rebuilds the search digest from the database (CLI-02).
  def refresh_search_text!
    return if destroyed? || !self.class.unscoped.exists?(id)

    update_column(:search_text, build_search_text)
  end

  def build_search_text
    methods = ClientContactMethod.unscoped.where(client_id: id).pluck(:kind, :value, :normalized)
    places = Property.unscoped.where(client_id: id).pluck(:label, :address_line1, :address_line2, :city, :region, :postal_code)
    [ display_name, company_name, *methods.flat_map { |kind, value, normalized| [ value, (normalized if kind == "phone") ] }, *places.flatten ]
      .compact_blank.join(" ").squish.downcase
  end

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

  # The form always offers an empty property; it's skipped only if nothing was entered in it.
  # A label, access notes or the billing box count, so a half-filled row reaches validation.
  def untouched_new_property?(attributes)
    attributes["id"].blank? && (Property::ADDRESS_FIELDS + %w[label access_notes]).all? { attributes[_1].blank? } &&
      !ActiveModel::Type::Boolean.new.cast(attributes["billing"])
  end

  def has_a_contact_method
    errors.add(:base, "Add an email or a phone number so you can reach this client.") if kept(contact_methods).empty?
  end

  def tags_are_short
    # On tag_list, the field the form shows.
    errors.add(:tag_list, "can have at most #{MAX_TAGS} tags") if tags.size > MAX_TAGS
    errors.add(:tag_list, "must each be 30 characters or fewer") if tags.any? { _1.length > 30 }
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
