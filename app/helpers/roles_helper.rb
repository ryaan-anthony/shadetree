# ACC-07: role pickers list the built-in roles, then the business's own, each only if the
# current member may give it to `target`.
module RolesHelper
  def role_options(target, custom_roles, built_in: BusinessUser::ROLES)
    options = built_in.map { [ _1.humanize, _1 ] } + custom_roles.map { [ _1.name, _1.choice ] }
    # A member keeps their own role in the list; a new invitee (unsaved) has none to keep.
    options.select { |_, choice| current_membership.can_assign_role?(target, choice) || (target.persisted? && choice == target.role_choice) }
  end

  def role_event_member(data) = User.find_by(id: data["member_id"])&.full_name || "a former member"

  # One line for the role's history.
  def role_event_summary(event)
    data = event.data
    words = ->(keys) { Array(keys).filter_map { Permissions::GROUPS.values.reduce(:merge)[_1.to_sym] }.map { _1.split(":").first } }
    case event.kind
    when "created" then "Created with #{pluralize(Array(data["permissions"]).size, "permission")}"
    when "assigned" then "Given to #{role_event_member(data)}"
    when "unassigned" then "Taken from #{role_event_member(data)}"
    when "deleted" then "Deleted; #{pluralize(data["members_moved"].to_i, "member")} moved to #{data["replacement"]}"
    when "changed"
      parts = []
      parts << "Renamed from #{data.dig("name", "from")}" if data["name"]
      if (change = data["permissions"])
        added = words.(Array(change["to"]) - Array(change["from"]))
        removed = words.(Array(change["from"]) - Array(change["to"]))
        parts << "Can now: #{added.join("; ")}" if added.any?
        parts << "No longer: #{removed.join("; ")}" if removed.any?
      end
      parts.join(". ").presence || "Changed"
    end
  end
end
