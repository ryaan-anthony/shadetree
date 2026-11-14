# Primary business entity containing core company information.
#
# The Business model represents a company or organization that provides services
# through the Shadetree platform. Each business has an owner (User) and can have
# multiple members (see BusinessUser).
#
# @attr [String] name Business name (required)
# @attr [String] industry Business industry type
# @attr [Text] address Business physical address
# @attr [Text] description Business description
# @attr [String] timezone Business timezone
# @attr [String] email Primary business email (required)
# @attr [String] phone Primary business phone
# @attr [String] website Business website URL
# @attr [String] currency Business currency (default: 'USD')
# @attr [String] brand_color Primary brand color (default: '#059669')
# @attr [String] logo_url Business logo URL
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
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true
  validates :currency, inclusion: { in: Money::CURRENCIES.keys }, allow_blank: true
  validate :timezone_must_be_known
  validates :industry, inclusion: {
    in: %w[landscaping maintenance cleaning hvac plumbing electrical roofing painting pool pest other]
  }, allow_blank: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_industry, ->(industry) { where(industry: industry) }

  # Industry display names
  INDUSTRIES = {
    "landscaping" => "Landscaping & Lawn Care",
    "maintenance" => "Home Maintenance & Repair",
    "cleaning" => "Cleaning Services",
    "hvac" => "HVAC Services",
    "plumbing" => "Plumbing Services",
    "electrical" => "Electrical Services",
    "roofing" => "Roofing Services",
    "painting" => "Painting Services",
    "pool" => "Pool & Spa Services",
    "pest" => "Pest Control",
    "other" => "Other Service Business"
  }.freeze

  # Instance methods

  # Opaque id for URLs and forms (ADR 0014).
  def to_param = uid

  def industry_name
    INDUSTRIES[industry] || industry
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

  def user_role(user)
    business_users.find_by(user: user)&.role
  end

  private

  def timezone_must_be_known
    return if timezone.blank? || ActiveSupport::TimeZone[timezone.to_s]

    errors.add(:timezone, "is not a time zone we recognise")
  end

  def set_default_brand_color
    self.brand_color = "#059669" if brand_color.blank?
  end

  def add_owner_to_business_users
    # Automatically add the owner to business_users with owner role
    business_users.create!(user: owner, role: "owner", active: true) unless business_users.exists?(user: owner)
  end
end
