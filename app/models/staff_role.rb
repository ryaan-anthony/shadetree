# Join table for staff members and business roles.
#
# The StaffRole model represents the many-to-many relationship between
# staff members and business roles. This allows staff members to have
# multiple roles within a business and roles to be assigned to multiple
# staff members.
#
# @attr [Integer] staff_member_id Associated staff member (foreign key, required)
# @attr [Integer] business_role_id Associated business role (foreign key, required)
class StaffRole < ApplicationRecord
  # Relationships
  belongs_to :staff_member
  belongs_to :business_role

  # Validations
  validates :staff_member_id, presence: true
  validates :business_role_id, presence: true
  validates :staff_member_id, uniqueness: { scope: :business_role_id, message: "already has this role assigned" }

  # Delegate methods for convenience
  delegate :name, to: :business_role, prefix: :role
  delegate :description, to: :business_role, prefix: :role
  delegate :permissions, to: :business_role
  delegate :is_default?, to: :business_role, prefix: :role
  delegate :full_name, to: :staff_member, prefix: :staff
  delegate :email, to: :staff_member, prefix: :staff
  delegate :business, to: :staff_member

  # Instance methods
  def role_name
    business_role.name
  end

  def staff_name
    staff_member.full_name
  end

  def has_permission?(category, action)
    business_role.has_permission?(category, action)
  end

  def default_role?
    business_role.is_default?
  end

  def custom_role?
    !business_role.is_default?
  end

  def assignment_description
    "#{staff_member.full_name} - #{business_role.name}"
  end
end
