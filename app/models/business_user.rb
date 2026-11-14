# Join model connecting users to businesses with role-based access
#
# @attr [Integer] user_id Foreign key to users
# @attr [Integer] business_id Foreign key to businesses
# @attr [String] role User's role in the business: owner, admin or technician (see ACC-04)
# @attr [Boolean] active Whether the user is active in this business
class BusinessUser < ApplicationRecord
  belongs_to :user
  belongs_to :business

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :business_id }
  validates :business_id, presence: true
  ROLES = %w[owner admin technician].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :active, inclusion: { in: [ true, false ] }

  # A business always keeps at least one active Owner (ACC-02).
  validate :keeps_an_active_owner, on: :update
  before_destroy :ensure_not_last_owner

  # Scopes
  scope :active, -> { where(active: true) }
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

  # Check if user can manage this business
  def can_manage?
    owner? || admin?
  end

  def last_active_owner?
    owner? && active? && business.business_users.active.owners.where.not(id:).none?
  end

  private

  LAST_OWNER_MESSAGE = "is the last owner. Make someone else an owner first".freeze

  def keeps_an_active_owner
    was_active_owner = role_was == "owner" && active_was
    still_active_owner = owner? && active?
    return unless was_active_owner && !still_active_owner
    return if business.business_users.active.owners.where.not(id:).exists?

    errors.add(:base, "#{user.full_name} #{LAST_OWNER_MESSAGE}")
  end

  def ensure_not_last_owner
    return if destroyed_by_association # the business itself is being deleted
    return unless last_active_owner?

    errors.add(:base, "#{user.full_name} #{LAST_OWNER_MESSAGE}")
    throw :abort
  end
end
