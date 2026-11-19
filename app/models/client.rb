# Someone a business works for (CLI-01). Clients never sign in (plan 04, D1): they're records
# the business keeps, reached through client links (PLT-12).
class Client < ApplicationRecord
  include BusinessOwned

  MAX_TAGS = 20
  # Associations that make a client undeletable (archive instead). Later specs add theirs:
  # requests (CLI-04), quotes (QTE-01), jobs (JOB-01), invoices (PAY-01).
  DOCUMENT_ASSOCIATIONS = %i[quotes service_requests jobs invoices].freeze

  has_many :contact_methods, -> { order(:position, :id) }, class_name: "ClientContactMethod",
           inverse_of: :client, dependent: :delete_all
  belongs_to :client_import, optional: true # CLI-06: the import that created it, for undo
  has_many :quotes, dependent: :restrict_with_exception
  has_many :jobs, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception # PAY-01
  has_many :service_requests, dependent: :restrict_with_exception # CLI-03
  has_many :events, class_name: "ClientEvent", dependent: :delete_all # CLI-05: the timeline
  has_many :timeline_notes, -> { order(:created_at) }, class_name: "ClientNote", dependent: :delete_all # CLI-05 (notes is the details field)
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

  # Editing the client, its contacts or properties counts as activity; archiving doesn't.
  before_save { self.last_activity_at = Time.current if new_record? || last_activity_at.nil? || edited? }
  # The search digest is rebuilt once per transaction, after commit, however many of the
  # client's rows changed (contact methods and properties queue it too).
  after_save :queue_search_refresh

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
  # address (CLI-02). A number-like word ("(555)", "010-01", "+1 555…") also matches its
  # digits, and a phone typed with the North American 1 matches without it, so phone
  # formatting doesn't matter while "12-14" or "28801-1234" still match addresses as typed.
  # Uses the trigram index on search_text.
  def self.search(query)
    search_terms(query).reduce(where(erased_at: nil)) do |scope, term| # INS-02: erased clients are never found
      variants = search_variants(term)
      scope.where(variants.map { "clients.search_text LIKE ?" }.join(" OR "), *variants.map { "%#{sanitize_sql_like(_1)}%" })
    end
  end

  # Words to match. A phone number written with spaces ("+1 (555) 010 0100") is one word.
  def self.search_terms(query)
    query.to_s.downcase
         .gsub(/[+(]?\d[\d()\-. ]*\d\)?/) { |number| number.count("0-9") >= 7 ? number.delete(" ") : number }
         .split.first(MAX_SEARCH_TERMS)
  end

  def self.search_variants(term)
    variants = [ term ]
    if term.match?(/\A[\d()+.\-]+\z/)
      digits = term.gsub(/\D/, "")
      variants << digits if digits.length >= 3
      variants << ClientContactMethod.normalize("phone", digits) if digits.length == 11
    end
    variants.compact.uniq
  end

  # Rebuilds search_text for the given clients in one statement, from what's committed, so
  # concurrent edits can't leave a stale digest. The migration's backfill uses the same SQL.
  def self.refresh_search_text(ids)
    ids = Array(ids).compact
    return if ids.empty?

    unscoped.where(id: ids).update_all(<<~SQL.squish)
      search_text = lower(concat_ws(' ', clients.display_name, clients.company_name,
        (SELECT string_agg(concat_ws(' ', m.value, CASE WHEN m.kind = 'phone' THEN m.normalized END), ' ')
           FROM client_contact_methods m WHERE m.client_id = clients.id),
        (SELECT string_agg(concat_ws(' ', p.label, p.address_line1, p.address_line2, p.city, p.region, p.postal_code), ' ')
           FROM properties p WHERE p.client_id = clients.id)))
    SQL
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

  # Rebuilds the search digest once the current transaction commits (at once if none is
  # open); repeated calls in one transaction rebuild it once.
  def queue_search_refresh
    return if @search_refresh_queued || id.nil?

    @search_refresh_queued = true
    ActiveRecord.after_all_transactions_commit do
      @search_refresh_queued = false
      self.class.refresh_search_text(id)
    end
  end

  def documents? = DOCUMENT_ASSOCIATIONS.any? { public_send(_1).exists? }
  def deletable? = !documents?
  def erased? = erased_at.present? # INS-02

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

  def edited? = (changed - %w[archived_at updated_at last_activity_at search_text]).any? || nested_records_changed_for_autosave?

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
