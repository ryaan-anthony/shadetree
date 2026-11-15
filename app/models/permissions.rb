# Named permissions and the built-in roles that grant them (ACC-04). This is the code form of the
# capability table in docs/plans/02-accounts.md; that table is the source of truth, and the two
# must change together. Features check permissions, never role names, so custom roles (ACC-07)
# only add a new row here.
module Permissions
  CATALOG = {
    billing: "Billing, plan, delete the business, transfer ownership",
    manage_owners: "Grant or remove the Owner role",
    manage_team: "Invite people, change roles (except Owner), deactivate members",
    business_settings: "Business profile, branding, hours, catalog, taxes",
    office: "Clients, requests, quotes, invoices and payments, for the whole business",
    schedule: "Schedule visits and assign them to people",
    field_work: "Own assigned visits: client contact, property, notes, photos, complete",
    export_data: "Export the business's data"
  }.freeze

  ROLES = {
    "owner" => CATALOG.keys,
    "admin" => %i[manage_team business_settings office schedule field_work export_data],
    "technician" => %i[field_work]
  }.freeze

  class UnknownPermission < ArgumentError; end

  def self.granted?(role, permission)
    raise UnknownPermission, "Unknown permission #{permission.inspect}" unless CATALOG.key?(permission.to_sym)

    ROLES.fetch(role.to_s, []).include?(permission.to_sym)
  end

  def self.roles_with(permission) = ROLES.select { |_, permissions| permissions.include?(permission.to_sym) }.keys
end
