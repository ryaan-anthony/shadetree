# Hierarchical service organization.
#
# The ServiceCategory model represents hierarchical service organization
# for businesses in the Shadetree platform. Categories can have parent-child
# relationships to create nested hierarchies, allowing businesses to organize
# their services in a structured way.
#
# @attr [Integer] business_id Associated business (foreign key, required)
# @attr [String] name Category name (required)
# @attr [String] description Category description
# @attr [Integer] parent_id Parent category (foreign key, optional)
# @attr [Integer] sort_order Display order (default: 0)
# @attr [Boolean] active Category status (default: true)
class ServiceCategory < ApplicationRecord
  # Relationships
  belongs_to :business
  belongs_to :parent, class_name: 'ServiceCategory', optional: true
  has_many :subcategories, class_name: 'ServiceCategory', foreign_key: 'parent_id', dependent: :destroy
  has_many :services, dependent: :destroy

  # Validations
  validates :business_id, presence: true
  validates :name, presence: true
  validates :name, uniqueness: { scope: [:business_id, :parent_id], message: "already exists in this category level for this business" }
  validates :sort_order, numericality: { greater_than_or_equal_to: 0 }
  validate :parent_must_belong_to_same_business
  validate :cannot_be_parent_of_itself

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :root_categories, -> { where(parent_id: nil) }
  scope :subcategories, -> { where.not(parent_id: nil) }
  scope :ordered, -> { order(:sort_order, :name) }
  scope :for_business, ->(business_id) { where(business_id: business_id) }

  # Instance methods
  def root_category?
    parent_id.nil?
  end

  def has_subcategories?
    subcategories.exists?
  end

  def has_services?
    services.exists?
  end

  def active?
    active
  end

  def inactive?
    !active
  end

  def full_name
    return name if root_category?
    "#{parent.full_name} > #{name}"
  end

  def hierarchy_level
    return 0 if root_category?
    parent.hierarchy_level + 1
  end

  def all_subcategories
    ServiceCategory.where(
      "parent_id = ? OR parent_id IN (?)",
      id,
      subcategories.pluck(:id)
    )
  end

  def all_services
    if has_subcategories?
      Service.joins(:service_category).where(
        service_category: [self] + all_subcategories.to_a
      )
    else
      services
    end
  end

  def services_count
    all_services.count
  end

  def active_services_count
    all_services.where(is_active: true).count
  end

  def can_be_deleted?
    !has_services? && !has_subcategories?
  end

  def deactivate!
    update!(active: false)
    # Optionally deactivate all subcategories and services
    subcategories.update_all(active: false)
    services.update_all(is_active: false)
  end

  def activate!
    update!(active: true)
    # Activate parent category if it exists and is inactive
    parent&.activate! if parent&.inactive?
  end

  def move_to_parent(new_parent)
    return false if new_parent && new_parent.business_id != business_id
    return false if new_parent == self
    return false if ancestors.include?(new_parent)

    update(parent: new_parent)
  end

  def ancestors
    return [] if root_category?
    [parent] + parent.ancestors
  end

  def descendants
    subcategories.flat_map { |sub| [sub] + sub.descendants }
  end

  def siblings
    if root_category?
      business.service_categories.root_categories.where.not(id: id)
    else
      parent.subcategories.where.not(id: id)
    end
  end

  private

  def parent_must_belong_to_same_business
    return unless parent_id.present?

    if parent && parent.business_id != business_id
      errors.add(:parent, "must belong to the same business")
    end
  end

  def cannot_be_parent_of_itself
    return unless parent_id.present?

    if parent_id == id
      errors.add(:parent, "cannot be the category itself")
    end
  end
end
