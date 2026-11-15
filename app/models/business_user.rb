# Join model connecting users to businesses with role-based access
#
# @attr [Integer] user_id Foreign key to users
# @attr [Integer] business_id Foreign key to businesses
# @attr [String] role User's role in the business: owner, admin or technician (see ACC-04)
# @attr [Boolean] active Whether the user is active in this business
class BusinessUser < ApplicationRecord
  belongs_to :user
  belongs_to :business

  before_validation { self.uid ||= SecureRandom.base58(BusinessOwned::UID_LENGTH) if new_record? }

  def to_param = uid

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :business_id }
  validates :business_id, presence: true
  ROLES = %w[owner admin technician].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :active, inclusion: { in: [ true, false ] }

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

  # Named permissions (ACC-04). Inactive memberships grant nothing.
  def can?(permission) = active? && Permissions.granted?(role, permission)

  # May `self` give `target` the role `new_role`? Admins manage the team but never Owners.
  def can_assign_role?(target, new_role)
    return false unless can?(:manage_team) && ROLES.include?(new_role.to_s) && target.business_id == business_id
    return can?(:manage_owners) if target.owner? || new_role.to_s == "owner"

    true
  end

  def last_active_owner?
    owner? && active? && business.business_users.active.owners.where.not(id:).none?
  end

  private

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

  def last_active_owner?
    owner? && active? && business.business_users.active.owners.where.not(id:).none?
  end

  private

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
