# CAT-07: a base a business works from (a branch, a yard). Every business has a primary
# location, made with the business; its address, contact details, time zone, hours and closures
# are the business profile's (Settings → Business and Hours), so a single-location business never
# sees locations. Other locations have their own, and adding one needs the plan's "locations"
# feature (BIL-01). A location is archived, never deleted: its documents keep pointing at it.
class Location < ApplicationRecord
  include BusinessOwned

  MAX = 50
  PRIMARY_NAME = "Main location"

  has_many :location_members, dependent: :delete_all
  has_many :members, through: :location_members, source: :user

  normalizes :name, with: ->(name) { name.to_s.squish }
  normalizes :email, :phone, with: ->(value) { value.to_s.strip.presence }
  normalizes :timezone, with: ->(zone) { ActiveSupport::TimeZone[zone.to_s.strip]&.tzinfo&.identifier || zone.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :business_id, case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :phone, length: { maximum: 40 }
  validates :address_line1, :address_line2, :city, :region, :postal_code, length: { maximum: 255 }
  validates :country, inclusion: { in: ->(_) { Country.codes }, message: "isn't supported yet" }
  validates :timezone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map { _1.tzinfo.identifier } }, message: "is not a time zone we recognise" }, allow_nil: true
  validate { WeeklyHours.new(weekly_hours).problems.each { errors.add(:weekly_hours, :invalid, message: _1) } unless primary? }
  validate :can_add, on: :create, unless: :primary?
  validate { errors.add(:base, "The main location can't be archived.") if primary? && archived_at }

  before_validation(on: :create) do
    next if primary?

    self.country ||= business&.country # the time zone is left empty: "same as the business", which follows it
    self.weekly_hours ||= business&.weekly_hours # a new branch starts with the business's hours
  end

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(primary: :desc).order(Arel.sql("lower(locations.name)"), :id) }

  def archived? = archived_at.present?

  # Where clients reach this location. The primary location's come from the business profile.
  def address_lines = primary? ? business.address_lines : AddressLines.for(self)
  def contact_phone = primary? ? business.phone : phone || business.phone
  def contact_email = primary? ? business.email : email || business.email
  # Named beside the business's name only while it has several locations.
  def contact_label = (name if business.multiple_locations?)

  # Time zone, hours and closures: the business's for the primary location (CAT-06).
  def time_zone = (primary? || timezone.blank? ? business.time_zone : ActiveSupport::TimeZone[timezone]) || business.time_zone
  def hours = primary? ? business.hours : WeeklyHours.new(weekly_hours)
  def today = time_zone.today

  def local_time(date, clock)
    hour, minute = clock.to_s.split(":").map { Integer(_1, 10) }
    time_zone.local(date.year, date.month, date.day, hour, minute || 0)
  end

  def closures = business.closures.where(location_id: (id unless primary?))

  # CAT-08: the tax rates new documents here start with: its own set, else the business's
  # defaults (always the business's for the main location). Archived rates drop out.
  def own_tax_rates? = !primary? && !tax_rate_ids.nil?
  def default_tax_rates = own_tax_rates? ? TaxRate.active.where(id: tax_rate_ids).ordered.to_a : TaxRate.default_set.to_a

  # Archiving: the primary can't be; a restore is an addition, so it needs the plan feature.
  def archive! = update!(archived_at: Time.current)

  def restore!
    raise ArgumentError, Location.plan_message unless business.entitlements.feature?(:locations)

    update!(archived_at: nil)
  end

  def self.plan_message = "More than one location isn't included in your plan. Your locations stay as they are, but you can't add more."

  private

  def can_add
    return unless business

    if !business.entitlements.feature?(:locations) then errors.add(:base, self.class.plan_message)
    elsif Location.count >= MAX then errors.add(:base, "A business can have up to #{MAX} locations.")
    end
  end
end
