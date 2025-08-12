# Business roles and permissions.
#
# The BusinessRole model represents business roles and permissions
# for staff members within businesses. Each role belongs to a business
# and defines specific permissions and access levels for staff members.
#
# @attr [Integer] business_id Associated business (foreign key, required)
# @attr [String] name Role name (required)
# @attr [String] description Role description
# @attr [JSON] permissions Permission settings
# @attr [Boolean] is_default Default role flag (default: false)
class BusinessRole < ApplicationRecord
  # Relationships
  belongs_to :business
  has_many :staff_roles, dependent: :destroy
  has_many :staff_members, through: :staff_roles

  # Validations
  validates :business_id, presence: true
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id, message: "already exists for this business" }
  validates :permissions, presence: true

  # Scopes
  scope :default_roles, -> { where(is_default: true) }
  scope :custom_roles, -> { where(is_default: false) }
  scope :by_name, ->(name) { where(name: name) }

  # Constants
  DEFAULT_PERMISSIONS = {
    dashboard: { view: false },
    appointments: { view: false, create: false, edit: false, delete: false },
    customers: { view: false, create: false, edit: false, delete: false },
    services: { view: false, create: false, edit: false, delete: false },
    pricing: { view: false, edit: false },
    locations: { view: false, create: false, edit: false, delete: false },
    staff: { view: false, create: false, edit: false, delete: false },
    reports: { view: false, export: false },
    settings: { view: false, edit: false },
    billing: { view: false, edit: false }
  }.freeze

  PERMISSION_CATEGORIES = %w[
    dashboard
    appointments
    customers
    services
    pricing
    locations
    staff
    reports
    settings
    billing
  ].freeze

  # Callbacks
  before_validation :set_default_permissions, if: :new_record?
  before_save :ensure_single_default_role, if: :is_default_changed?

  # Instance methods
  def default_role?
    is_default?
  end

  def custom_role?
    !is_default?
  end

  def has_permission?(category, action)
    return false unless permissions.is_a?(Hash)
    return false unless permissions[category.to_s].is_a?(Hash)

    permissions[category.to_s][action.to_s] == true
  end

  def grant_permission(category, action)
    ensure_permissions_structure
    permissions[category.to_s] ||= {}
    permissions[category.to_s][action.to_s] = true
    save
  end

  def revoke_permission(category, action)
    ensure_permissions_structure
    return unless permissions[category.to_s].is_a?(Hash)

    permissions[category.to_s][action.to_s] = false
    save
  end

  def permission_summary
    return {} unless permissions.is_a?(Hash)

    summary = {}
    PERMISSION_CATEGORIES.each do |category|
      category_perms = permissions[category] || {}
      granted = category_perms.select { |_, value| value == true }
      summary[category] = granted.keys
    end
    summary
  end

  def total_permissions_count
    return 0 unless permissions.is_a?(Hash)

    permissions.values.sum do |category_perms|
      next 0 unless category_perms.is_a?(Hash)
      category_perms.count { |_, value| value == true }
    end
  end

  def can_access_admin?
    has_permission?(:settings, :view) || has_permission?(:staff, :view)
  end

  def is_admin_role?
    total_permissions_count >= 10 # Arbitrary threshold for admin-level access
  end

  def duplicate_for_business(target_business)
    new_role = self.dup
    new_role.business = target_business
    new_role.name = "#{name} (Copy)"
    new_role.is_default = false
    new_role.save
    new_role
  end

  private

  def set_default_permissions
    self.permissions = DEFAULT_PERMISSIONS.deep_dup if permissions.blank?
  end

  def ensure_permissions_structure
    self.permissions = DEFAULT_PERMISSIONS.deep_dup if permissions.blank?
  end

  def ensure_single_default_role
    if is_default? && is_default_changed?
      # Set all other roles for this business to not default
      BusinessRole.where(business: business).where.not(id: id).update_all(is_default: false)
    end
  end
end
