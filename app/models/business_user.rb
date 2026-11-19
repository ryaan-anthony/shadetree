# Join model connecting users to businesses with role-based access
#
# @attr [Integer] user_id Foreign key to users
# @attr [Integer] business_id Foreign key to businesses
# @attr [String] role User's role in the business: owner, admin or technician (see ACC-04)
# @attr [Boolean] active Whether the user is active in this business
class BusinessUser < ApplicationRecord
  belongs_to :user
  belongs_to :business
  belongs_to :default_location, class_name: "Location", optional: true # CAT-07

  before_validation { self.uid ||= SecureRandom.base58(BusinessOwned::UID_LENGTH) if new_record? }

  def to_param = uid

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :business_id }
  validates :business_id, presence: true
  ROLES = %w[owner admin technician].freeze
  CUSTOM = "custom" # ACC-07: a business's own role, in role_id

  validates :role, presence: true, inclusion: { in: ROLES + [ CUSTOM ] }
  validates :role_id, presence: true, if: :custom_role?
  validate :custom_role_in_this_business
  validates :active, inclusion: { in: [ true, false ] }
  validate { errors.add(:default_location, "isn't available") if default_location && default_location.business_id != business_id }

  # A membership never moves between users or businesses.
  attr_readonly :user_id, :business_id

  # A business always keeps at least one active Owner (ACC-02). Checked against the database
  # under a lock on the business row, so concurrent demotions can't both pass.
  before_update :keeps_an_active_owner
  before_destroy :ensure_not_last_owner

  # Scopes
  scope :active, -> { where(active: true) }
  scope :deactivated, -> { where(active: false) }
  scope :owners, -> { where(role: "owner") }
  scope :admins, -> { where(role: "admin") }
  scope :technicians, -> { where(role: "technician") }

  # CAT-07: the locations this member works at.
  def locations = Tenancy.with_business(business) { Location.where(id: LocationMember.where(user_id:).select(:location_id)).ordered.to_a }

  # Their home location: their default while it's active, else the only active location they
  # work at; nil when neither (CAT-07). The location filter starts here.
  def home_location
    Tenancy.with_business(business) do
      active = Location.active.where(id: LocationMember.where(user_id:).select(:location_id)).to_a
      (default_location unless default_location&.archived?) || (active.first if active.one?)
    end
  end

  # Where documents this member creates start: their home location, else the main location.
  def document_location = home_location || business.primary_location

  # Check if user is owner of this business
  def owner?
    role == "owner"
  end

  # Check if user is admin of this business
  def admin?
    role == "admin"
  end

  # Ends access to this business immediately (BusinessContext checks every request). The user
  # and their name on past records stay; reactivate! restores the same role.
  def deactivate! = update!(active: false, deactivated_at: Time.current)
  def reactivate! = update!(active: true, deactivated_at: nil)

  # Named permissions (ACC-04). Inactive memberships grant nothing; a custom role grants what
  # it lists, never an Owner-only permission (ACC-07).
  def can?(permission)
    return false unless active?
    return Permissions.granted?(role, permission) unless custom_role?

    Permissions::CATALOG.fetch(permission.to_sym) { raise Permissions::UnknownPermission, permission.inspect }
    custom_role_record&.grants?(permission) || false
  end

  def custom_role? = role == CUSTOM

  # The custom role, loaded within this membership's business whatever the current tenant.
  def custom_role_record
    return unless role_id

    @custom_role_record = nil if @custom_role_record && @custom_role_record.id != role_id
    @custom_role_record ||= Role.unscoped.find_by(id: role_id, business_id:)
  end

  # "Owner", "Technician", or the custom role's name.
  def role_name = custom_role? ? custom_role_record&.name.to_s : role.humanize

  # The value role pickers use: "admin", or "role:<uid>" for a custom role.
  def role_choice = custom_role? ? custom_role_record&.choice : role

  # Sets the role from a picker's value. Returns false for one that isn't valid here.
  def assign_role_choice(choice)
    attributes = BusinessUser.role_attributes(choice, business) or return false
    assign_attributes(attributes)
    true
  end

  # { role:, role_id: } for a picker's value in `business`, or nil.
  def self.role_attributes(choice, business)
    choice = choice.to_s
    return { role: choice, role_id: nil } if ROLES.include?(choice)

    uid = choice.delete_prefix("role:")
    role = choice.start_with?("role:") && Role.unscoped.find_by(business_id: business.id, uid:)
    role ? { role: CUSTOM, role_id: role.id } : nil
  end

  # NTF-02: whether this member wants a notification type by email: their choice, else the type's default.
  def email_notification?(kind) = notification_emails.fetch(kind.to_s) { NotificationType.fetch(kind).email_by_default } == true

  # May `self` give `target` the role `new_role` (a picker's value)? Admins manage the team but
  # never Owners. Nobody hands out, or changes the role of someone with, a permission they don't
  # have themselves (a custom "team lead" can't make Admins, or promote themselves).
  # A custom role needs the plan feature (ACC-07); on a plan without it, members keep theirs
  # but nobody new is given one.
  def can_assign_role?(target, new_role)
    new_role = new_role.to_s
    return false unless can?(:manage_team) && target.business_id == business_id
    return false unless covers?(target.permission_set) && covers?(BusinessUser.permissions_for(new_role, business))
    keeping = target.persisted? && new_role == target.role_choice # deactivating or reactivating
    return false unless ROLES.include?(new_role) || ((keeping || custom_roles_allowed?) && BusinessUser.role_attributes(new_role, business))
    return can?(:manage_owners) if target.owner? || new_role == "owner"

    true
  end

  def custom_roles_allowed? = business.entitlements.feature?(:custom_roles)

  # The permissions this membership's role grants (ignoring whether it's active).
  def permission_set = custom_role? ? Array(custom_role_record&.permissions).map(&:to_sym) : Permissions::ROLES.fetch(role, [])

  # The permissions a picker's value would grant in `business` (nil for an unknown value).
  def self.permissions_for(choice, business)
    choice = choice.to_s
    return Permissions::ROLES[choice] if ROLES.include?(choice)

    role = choice.start_with?("role:") && Role.unscoped.find_by(business_id: business.id, uid: choice.delete_prefix("role:"))
    role ? role.permissions.map(&:to_sym) : nil
  end

  private def covers?(permissions) = !permissions.nil? && permissions.all? { can?(_1) }

  def last_active_owner?
    owner? && active? && business.business_users.active.owners.where.not(id:).none?
  end

  private

  def custom_role_in_this_business
    errors.add(:role, "isn't available") if role_id && custom_role_record.nil?
  end

  LAST_OWNER_MESSAGE = "is the last owner. Make someone else an owner first".freeze

  # Was this membership an active Owner in the database (ignoring unsaved changes)?
  def persisted_active_owner? = attribute_in_database(:role) == "owner" && attribute_in_database(:active)

  def other_active_owner_exists?
    Business.lock.find(business_id) # serialise owner changes per business
    business.business_users.active.owners.where.not(id:).exists?
  end

  def keeps_an_active_owner
    return unless persisted_active_owner? && !(owner? && active?)
    return if other_active_owner_exists?

    errors.add(:base, "#{user.full_name} #{LAST_OWNER_MESSAGE}")
    throw :abort
  end

  def ensure_not_last_owner
    return if destroyed_by_association&.active_record == Business # the business itself is being deleted
    return unless persisted_active_owner?
    return if other_active_owner_exists?

    errors.add(:base, "#{user.full_name} #{LAST_OWNER_MESSAGE}")
    throw :abort
  end
end
