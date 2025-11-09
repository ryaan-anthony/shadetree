# Join model connecting users to businesses with role-based access
#
# @attr [Integer] user_id Foreign key to users
# @attr [Integer] business_id Foreign key to businesses
# @attr [String] role User's role in the business (owner, admin, member)
# @attr [Boolean] active Whether the user is active in this business
class BusinessUser < ApplicationRecord
  belongs_to :user
  belongs_to :business

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :business_id }
  validates :business_id, presence: true
  validates :role, presence: true, inclusion: { in: %w[owner admin member] }
  validates :active, inclusion: { in: [true, false] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :owners, -> { where(role: 'owner') }
  scope :admins, -> { where(role: 'admin') }
  scope :members, -> { where(role: 'member') }

  # Check if user is owner of this business
  def owner?
    role == 'owner'
  end

  # Check if user is admin of this business
  def admin?
    role == 'admin'
  end

  # Check if user can manage this business
  def can_manage?
    owner? || admin?
  end
end
