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

- [ ] The permission catalog (the named capabilities behind ACC-04's capability table) is
      documented and shown in plain language, grouped by area.
- [ ] Owners can create, edit, duplicate and delete custom roles by choosing permissions; the
      built-in roles are shown read-only and can be duplicated as a starting point.
- [ ] Some permissions are Owner-only and can't be granted to custom roles (billing, deleting
      the business, managing Owners, connecting the payment account).
- [ ] Members can be assigned a custom role wherever roles are chosen (invitations, team page).
- [ ] Deleting a role in use requires choosing a replacement role for its members.
- [ ] Permission changes take effect on the member's next request; changes are recorded.
- [ ] Navigation, actions and notifications (NTF-02) follow the member's permissions.
- [ ] Custom roles are a plan feature (entitlement from BIL-01); on downgrade, existing custom
      roles keep working but can't be edited or newly assigned.
- [ ] Tests cover each permission's enforcement through a custom role, Owner-only permissions,
      role deletion with reassignment, and tenancy.

## Out of scope

- Per-member permission overrides, record-level sharing rules, location-scoped roles (see
  CAT-07 open questions).

## Open questions

- Should custom roles be limited to paid plans? Recommended: Pro and above.
- Should a role be scoped to specific locations (CAT-07)? Recommend deciding after CAT-07 ships.
