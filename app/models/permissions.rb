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
    office: "Clients, requests, quotes, jobs, invoices and payments, for the whole business",
    schedule: "Schedule visits and assign them to people",
    field_work: "Own assigned visits: client contact, property, notes, photos, complete",
    quote_requests: "Quote requests assigned to them: create and edit their own drafts", # QTE-07
    export_data: "Export the business's data"
  }.freeze

  ROLES = {
    "owner" => CATALOG.keys,
    "admin" => %i[manage_team business_settings office schedule field_work quote_requests export_data],
    "technician" => %i[field_work]
  }.freeze

  # ACC-07: what a custom role may include, grouped by area, in plain words. Owner-only
  # permissions (billing and the plan, deleting the business, the payment account, who's an
  # Owner) are never granted by a custom role.
  OWNER_ONLY = %i[billing manage_owners].freeze
  GROUPS = {
    "Work" => {
      office: "See and manage all clients, requests, quotes, jobs, invoices and payments",
      schedule: "Schedule visits and assign them to people",
      field_work: "Work their own assigned visits: see the client and property, add notes and photos, complete them",
      quote_requests: "Quote the requests given to them: draft the quote, with catalog prices, and edit it until it's sent " \
                      "(with the visits permission above, so the requests reach them)"
    },
    "Business" => {
      business_settings: "Change the business profile, branding, hours, catalog and taxes",
      manage_team: "Invite people and change their roles (never Owners)",
      export_data: "Export all the business's data, invoices and payments included"
    }
  }.freeze
  GRANTABLE = GROUPS.values.flat_map(&:keys).freeze

  class UnknownPermission < ArgumentError; end

  def self.granted?(role, permission)
    raise UnknownPermission, "Unknown permission #{permission.inspect}" unless CATALOG.key?(permission.to_sym)

    ROLES.fetch(role.to_s, []).include?(permission.to_sym)
  end

  def self.roles_with(permission) = ROLES.select { |_, permissions| permissions.include?(permission.to_sym) }.keys
end
