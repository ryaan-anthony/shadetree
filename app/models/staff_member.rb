# Staff member profiles and information.
#
# The StaffMember model represents staff member profiles and information
# for businesses in the Shadetree platform. Each staff member belongs to a
# business and is associated with a user account, with status tracking and
# role assignments.
#
# @attr [Integer] business_id Associated business (foreign key, required)
# @attr [Integer] user_id Associated user account (foreign key, required)
# @attr [String] status Staff status - 'active', 'inactive', 'pending' (default: 'active')
class StaffMember < ApplicationRecord
  # Relationships
  belongs_to :business
  belongs_to :user
  has_many :staff_roles, dependent: :destroy
  has_many :roles, through: :staff_roles
  has_many :staff_availabilities, dependent: :destroy
  has_many :staff_service_assignments, dependent: :destroy
  has_many :services, through: :staff_service_assignments

  # Validations
  validates :business_id, presence: true
  validates :user_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive pending] }
  validates :user_id, uniqueness: { scope: :business_id, message: "is already a staff member for this business" }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :pending, -> { where(status: 'pending') }
  scope :by_status, ->(status) { where(status: status) }

  # Instance methods
  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  def pending?
    status == 'pending'
  end

  def full_name
    user.full_name
  end

  def email
    user.email
  end

  def first_name
    user.first_name
  end

  def last_name
    user.last_name
  end

  def has_role?(role_name)
    roles.exists?(name: role_name)
  end

  def primary_role
    roles.first
  end

  def role_names
    roles.pluck(:name)
  end

  def assigned_services
    services.where(is_active: true)
  end

  def can_perform_service?(service)
    services.include?(service)
  end

  def available_on_day?(day_of_week)
    staff_availabilities.where(day_of_week: day_of_week, is_available: true).exists?
  end

  def availability_for_day(day_of_week)
    staff_availabilities.where(day_of_week: day_of_week, is_available: true)
  end

  def deactivate!
    update!(status: 'inactive')
  end

  def activate!
    update!(status: 'active')
  end

  def set_pending!
    update!(status: 'pending')
  end
end
