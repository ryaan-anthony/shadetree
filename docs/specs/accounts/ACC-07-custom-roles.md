---
id: ACC-07
title: Custom roles
domain: accounts
milestone: M5
depends_on: [ACC-04, BIL-01]
---
# ACC-07 · Custom roles

> Requirements: [02-accounts](../../plans/02-accounts.md) R14

## Summary

Owner, Admin and Technician fit most crews, but some businesses need something in between — an
office assistant who can schedule but not see invoices, or a lead tech who can build quotes.
Let Owners create custom roles from a fixed catalog of permissions, alongside the built-in roles.

## User stories

- As an owner, I want a "Dispatcher" role that can schedule visits but can't see prices or
  payments.
- As an owner, I want a "Lead tech" role that can create quotes in the field.
- As an owner, I want to see exactly what each role can do before assigning it.

## Acceptance criteria

- [x] The permission catalog (the named capabilities behind ACC-04's capability table) is
      documented and shown in plain language, grouped by area.
- [x] Owners can create, edit, duplicate and delete custom roles by choosing permissions; the
      built-in roles are shown read-only and can be duplicated as a starting point.
- [x] Some permissions are Owner-only and can't be granted to custom roles (billing, deleting
      the business, managing Owners, connecting the payment account).
- [x] Members can be assigned a custom role wherever roles are chosen (invitations, team page).
- [x] Deleting a role in use requires choosing a replacement role for its members.
- [x] Permission changes take effect on the member's next request; changes are recorded.
- [x] Navigation, actions and notifications (NTF-02) follow the member's permissions.
- [x] Custom roles are a plan feature (entitlement from BIL-01); on downgrade, existing custom
      roles keep working but can't be edited or newly assigned.
- [x] Tests cover each permission's enforcement through a custom role, Owner-only permissions,
      role deletion with reassignment, and tenancy.

## Out of scope

- Per-member permission overrides, record-level sharing rules, location-scoped roles (see
  CAT-07 open questions).

## Decisions

- **Pro and above** (recommendation accepted, M5 planning): the `custom_roles` plan feature.
- **Location-scoped roles wait for CAT-07** (recommendation accepted).
- **Owners manage roles; anyone who manages the team can give them**, within a rule: nobody
  gives a role, or changes someone's role, carrying a permission they don't have themselves
  (so nobody promotes themselves). (Admins hold every grantable permission, so for them
  nothing changes; a custom "team lead" can hand out Technician but not Admin. Since Technicians
  quote assigned requests (QTE-07, 2026-11-22), that lead needs "Quote assigned requests" too.)
- A team-manager role without "Quote assigned requests" can't invite or manage Technicians
  (who have it since QTE-07): the rule stays, and a business adds the permission to the role
  (owner, 2026-11-22).
- **Owner-only, never in a custom role:** `billing` (plan, deleting the business, the payment
  account) and `manage_owners`.

## Implementation notes

- `Permissions::GROUPS` holds the grantable permissions in plain words, by area (Work,
  Business); `OWNER_ONLY` the rest. The capability table in 02-accounts stays the source.
- `Role` (per business, up to 20, names unique ignoring case and never a built-in name) lists
  permissions; a member or invitation with one has role "custom" and `role_id`.
  `BusinessUser#can?` asks the role, so navigation, actions and notifications (all permission
  based) follow it from the next request. `role_name` / `role_choice` replace `role` where
  people see or pick roles (team page, invitations, emails, sidebar, the My day welcome, which
  now greets anyone without office access).
- Team → Roles (`manage_owners`): built-in roles read-only (Admin and Technician can be
  duplicated), the business's own with member counts; new (blank or from another role), edit,
  duplicate, and delete, which asks for a replacement when anyone (or a pending invitation) has
  the role. `RoleEvent` records created / changed (name, permissions added and removed) /
  assigned / deleted, shown as the role's history.
- Plan gating: without the feature, roles are read-only (still deletable), can't be given to
  anyone new (a pending invitation with one becomes Technician on acceptance), and keep
  working; members who have one can still be deactivated and reactivated.
- Pages follow the role: Home sends someone without office access to the first page they can
  use (My day, the schedule, the team), the sidebar shows My day and Schedule by their own
  permissions, the schedule hides job links from people without office access (and visit saves
  return to the schedule), and only people who can work visits are offered as assignees.

## Open questions

- None.
