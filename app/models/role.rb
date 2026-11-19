# ACC-07: a business's own role, built from the grantable permissions (Permissions::GROUPS),
# beside the built-in Owner, Admin and Technician. Members and invitations point at it with
# role "custom". Changes are recorded as RoleEvents; a role in use is deleted by moving its
# members (and pending invitations) to another role first (#replace_with!).
class Role < ApplicationRecord
  include BusinessOwned

  MAX = 20

  has_many :business_users, dependent: :restrict_with_exception
  has_many :invitations, dependent: :restrict_with_exception
  has_many :events, class_name: "RoleEvent", dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }
  normalizes :permissions, with: ->(list) { Array(list).map(&:to_s).compact_blank.uniq.sort }

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { scope: :business_id, case_sensitive: false }
  validate :name_isnt_built_in, :only_grantable_permissions
  validate :within_limit, on: :create

  scope :ordered, -> { order(Arel.sql("lower(name)")) }

  def grants?(permission) = permissions.include?(permission.to_s) && Permissions::GRANTABLE.include?(permission.to_sym)

  # The choice a role picker sends: "admin", "technician", or "role:<uid>" for this one.
  def choice = "role:#{uid}"

  def in_use? = business_users.exists? || invitations.pending.exists?

  # Moves everyone with this role (and its pending invitations) to `replacement` (a built-in role
  # name or another Role), then deletes it, all at once.
  def replace_with!(replacement, by:)
    transaction do
      attributes = replacement.is_a?(Role) ? { role: "custom", role_id: replacement.id } : { role: replacement.to_s, role_id: nil }
      raise ArgumentError, "can't replace a role with Owner" if attributes[:role] == "owner"

      moved = business_users.count
      business_users.update_all(attributes.merge(updated_at: Time.current))
      invitations.update_all(attributes.merge(updated_at: Time.current))
      RoleEvent.record!(self, "deleted", by:, members_moved: moved, replacement: replacement.is_a?(Role) ? replacement.name : replacement.to_s.humanize)
      destroy!
    end
  end

  private

  def name_isnt_built_in
    errors.add(:name, "is a built-in role") if BusinessUser::ROLES.any? { _1.casecmp?(name.to_s) }
  end

  def only_grantable_permissions
    extra = permissions - Permissions::GRANTABLE.map(&:to_s)
    errors.add(:permissions, "can't include #{extra.to_sentence} (Owner-only or unknown)") if extra.any?
    errors.add(:permissions, "need at least one") if permissions.empty?
  end

  def within_limit
    errors.add(:base, "A business can have up to #{MAX} roles of its own.") if self.class.count >= MAX
  end
end
