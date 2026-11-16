# Primary business entity containing core company information.
#
# The Business model represents a company or organization that provides services
# through the Shadetree platform. Each business has an owner (User) and can have
# multiple members (see BusinessUser).
#
# @attr [String] name Business name (required)
# @attr [String] industry Business industry type
# @attr [String] address_line1/address_line2/city/region/postal_code/country Structured address
# @attr [Text] description Business description
# @attr [String] timezone Business timezone
# @attr [String] email Primary business email (required)
# @attr [String] phone Primary business phone
# @attr [String] website Business website URL
# @attr [String] currency Business currency (default: 'USD')
# @attr [String] brand_color Primary brand color (default: Branding::DEFAULT_COLOR)
# @attr [Boolean] active Business status (default: true)
# @attr [Integer] owner_id Business owner (foreign key to users)
class Business < ApplicationRecord
  # Relationships
  belongs_to :owner, class_name: "User"
  has_many :business_users, dependent: :destroy
  has_many :users, through: :business_users

  # Callbacks
  before_validation { self.uid ||= SecureRandom.base58(BusinessOwned::UID_LENGTH) if new_record? }
  before_save :set_default_brand_color
  after_create :add_owner_to_business_users

  # Validations
  validates :name, presence: true, length: { maximum: 120 }
  # Required when an owner sets a business up (ACC-02); records created elsewhere may skip it.
  validates :industry, presence: { message: "helps us set things up. Pick the closest one" }, on: :setup
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :owner_id, presence: true
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "should be a color like #047857" }, allow_blank: true
  normalizes :brand_color, with: ->(color) { color.to_s.strip.downcase.sub(/\A(?=\h{6}\z)/, "#").presence }

  # CAT-02: the uploaded logo. Branding::LOGO_SIZES are the sizes pages, emails and PDFs use.
  LOGO_TYPES = LogoUpload::FORMATS.values.map(&:first).freeze
  LOGO_MAX_BYTES = LogoUpload::MAX_BYTES
  has_one_attached :logo do |attachable|
    Branding::LOGO_SIZES.each { |name, transform| attachable.variant name, **transform, saver: { strip: true } }
  end
  validate { errors.add(:logo, @logo_error) if @logo_error }
  attr_accessor :remove_logo
  before_save { logo.purge_later if ActiveModel::Type::Boolean.new.cast(remove_logo) && attachment_changes["logo"].nil? && logo.attached? }
  validates :currency, inclusion: { in: Money::CURRENCIES.keys }, allow_blank: true
  validate :timezone_must_be_known
  validates :industry, inclusion: { in: ->(_) { Industry.keys }, message: "isn't one we know" }, allow_blank: true
  validates :country, inclusion: { in: ->(_) { Country.codes }, message: "isn't supported yet" }
  validates :website, format: { with: %r{\Ahttps?://\S+\.\S+\z}i, message: "should start with https://" }, allow_blank: true
  validates :address_line1, :address_line2, :city, :region, :postal_code, length: { maximum: 255 }
  validates :quote_expiry_days, numericality: { only_integer: true, in: 1..365 }
  validates :invoice_due_days, numericality: { only_integer: true, in: 0..365 }
  validates :quote_number_prefix, :invoice_number_prefix,
            format: { with: /\A[A-Z0-9][A-Z0-9-]{0,7}\z/, message: "use up to 8 capital letters, digits or dashes" }
  validates :quote_terms, :invoice_terms, length: { maximum: 5_000 }
  before_validation :default_currency_from_country, if: :new_record?
  normalizes :quote_number_prefix, :invoice_number_prefix, with: ->(prefix) { prefix.to_s.strip.upcase }
  # Adds https:// only when no scheme was typed, so "ftp://…" still fails the format check.
  normalizes :website, with: ->(url) { url.strip.then { _1.blank? || _1.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? _1 : "https://#{_1}" } }
  # Store IANA identifiers ("America/New_York"), which is what the settings select offers.
  normalizes :timezone, with: ->(zone) { ActiveSupport::TimeZone[zone.to_s.strip]&.tzinfo&.identifier || zone.to_s.strip.presence }

  # CLI-03: the public request page lives at /request/<handle>. Owners and Admins can change
  # the handle (old links then stop working); new businesses get one from their name.
  HANDLE_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])\z/
  RESERVED_HANDLES = %w[admin api app assets help login new request requests settings shadetree signup support www].freeze
  normalizes :handle, with: ->(handle) { handle.to_s.strip.downcase }
  normalizes :request_form_intro, with: ->(text) { text.to_s.strip.presence }
  before_validation(if: :new_record?) { self.handle = self.class.available_handle(name) if handle.blank? } # any context (setup)
  validates :handle, presence: true, uniqueness: { case_sensitive: false },
                     format: { with: HANDLE_FORMAT, message: "use 3 to 40 lowercase letters, digits or dashes, starting and ending with a letter or digit" },
                     exclusion: { in: RESERVED_HANDLES, message: "is reserved. Try another" }
  validates :request_form_intro, length: { maximum: 500 }

  # A free handle based on a business name ("Oakline Lawn & Care" -> "oakline-lawn-care").
  def self.available_handle(name)
    base = name.to_s.parameterize.first(34).sub(/-+\z/, "")
    base = "business-#{base}".first(34).sub(/-+\z/, "") if base.length < 3 || RESERVED_HANDLES.include?(base)
    candidates = [ base, *(2..50).map { "#{base}-#{_1}" } ]
    taken = where(handle: candidates).pluck(:handle)
    candidates.find { !taken.include?(_1) } || "#{base}-#{SecureRandom.alphanumeric(4).downcase}"
  end

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_industry, ->(industry) { where(industry: industry) }


  # Instance methods

  # Opaque id for URLs and forms (ADR 0014).
  def to_param = uid

  # How long a visit usually takes in this industry (CAT-05), for scheduling defaults.
  def default_visit_minutes = IndustryPreset.for(industry)&.default_visit_minutes || 60

  def industry_name = Industry.name_for(industry) || industry

  def country_entry = Country.find(country)

  # Address lines as they appear on documents, skipping blanks.
  def address_lines
    city_line = [ city, [ region, postal_code ].compact_blank.join(" ") ].compact_blank.join(", ")
    [ address_line1, address_line2, city_line, (country_entry&.name if country != "US") ].compact_blank
  end

  # What a quote or invoice copies when it's created, so later profile changes never alter it
  # (CAT-01). QTE-01 and INV-01 store this on the document.
  def document_snapshot
    {
      "name" => name, "email" => email, "phone" => phone, "website" => website,
      "address_lines" => address_lines, "currency" => currency_code
    }
  end

  # Money, time and numbering conventions (ADR 0013).

  def currency_code = currency.presence || "USD"

  def money(amount) = Money.parse(amount, currency_code)

  # The business's ActiveSupport::TimeZone. Times are stored in UTC and shown in this zone.
  def time_zone
    ActiveSupport::TimeZone[timezone.to_s] || ActiveSupport::TimeZone["UTC"]
  end

  # Run a block (a job, a mailer, a PDF render) in the business's zone.
  def use_time_zone(&) = Time.use_zone(time_zone, &)

  # Today in the business's zone; use this, not Date.today, for due dates and "today" views.
  def today = time_zone.today

  # A wall-clock time on a local date, e.g. a 09:00 visit on 2026-03-08, as a TimeWithZone.
  # Times skipped by a spring-forward move ahead an hour (02:30 becomes 03:30); times repeated
  # by a fall-back resolve to the first occurrence.
  def local_time(date, clock)
    hour, minute = clock.to_s.split(":").map { Integer(_1, 10) }
    time_zone.local(date.year, date.month, date.day, hour, minute || 0)
  end

  def next_document_number(kind) = DocumentNumber.next!(self, kind)

  def add_user(user, role: "technician")
    business_users.create!(user: user, role: role, active: true)
  end

  def remove_user(user)
    business_users.where(user: user).destroy_all
  end

  # Logo, brand color and what's derived from them (CAT-02).
  def branding = Branding.new(self)

  # Every logo goes through LogoUpload: decoded, size-checked and stripped of metadata. A
  # rejected file leaves the current logo in place and adds an error on save; a blank
  # value (no file chosen) changes nothing.
  def logo=(attachable)
    result = LogoUpload.prepare(attachable)
    @logo_error = result.error
    super(result.attachable) if result.attachable
  end

  def user_role(user)
    business_users.find_by(user: user)&.role
  end

  private

  def default_currency_from_country
    self.currency = Country.currency_for(country) if currency.blank? || (currency == "USD" && country != "US" && !currency_changed?)
  end

  def timezone_must_be_known
    return if timezone.blank? || ActiveSupport::TimeZone[timezone.to_s]

    errors.add(:timezone, "is not a time zone we recognise")
  end

  def set_default_brand_color
    self.brand_color = Branding::DEFAULT_COLOR if brand_color.blank?
  end

  def add_owner_to_business_users
    # Automatically add the owner to business_users with owner role
    business_users.create!(user: owner, role: "owner", active: true) unless business_users.exists?(user: owner)
  end
end
