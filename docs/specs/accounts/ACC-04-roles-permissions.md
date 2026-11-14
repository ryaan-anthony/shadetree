---
id: ACC-04
title: Roles & permissions
domain: accounts
milestone: M1
depends_on: [ACC-02]
---
# ACC-04 · Roles & permissions

> Requirements: [02-accounts](../../plans/02-accounts.md) R10, R11

## Summary

Establish the three fixed roles — Owner, Admin, Technician — and a single, consistent way to
enforce what each can do, so every later feature declares its rules in one place and tests them
the same way.

## User stories

- As an owner, I want my technicians to see only their own visits and the client details they
  need, not prices or the whole client list.
- As an admin, I want to manage day-to-day operations without access to billing.
- As a developer, I want a standard way to declare and test "who can do this".

## Acceptance criteria

- [ ] Each membership has exactly one role: Owner, Admin or Technician; Owners and Admins can
      change roles per the capability table in 02-accounts (Admins cannot grant or revoke Owner).
- [ ] A central authorization approach is used for every staff action; actions without an
      explicit rule are denied by default.
- [ ] Rules are expressed as named permissions mapped to roles (not role-name checks scattered
      through features), so custom roles (ACC-07) need no feature changes.
- [ ] Unauthorized actions return a consistent response (hidden in navigation, "not found" or
      "not allowed" page as appropriate) and are logged without PII.
- [ ] Navigation and actions are shown or hidden per role (e.g. Technicians don't see Settings,
      Clients list, Billing).
- [ ] A shared test pattern lets any feature assert the role matrix for its actions.
- [ ] The capability table in 02-accounts is the documented source of truth and is linked from
      the contributor guide.

## Out of scope

- Custom roles (ACC-07). Per-member permission overrides (not planned).
- Per-business setting allowing Technicians to see prices (JOB-04 adds that toggle).

## Open questions

- Should Technicians be able to view (read-only) the full client list for phone lookups?
  Recommend no; they see clients only through assigned visits.
