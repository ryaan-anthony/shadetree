---
id: ACC-06
title: Account settings & deletion
domain: accounts
milestone: M5
depends_on: [ACC-01]
---
# ACC-06 · Account settings & deletion

> Requirements: [02-accounts](../../plans/02-accounts.md) R3

## Summary

A person manages their own identity — name, email, password, sessions — independent of any
business, and can delete their account in line with privacy expectations, without orphaning a
business that others depend on.

## User stories

- As a user, I want to update my name, email and password in one place.
- As a user, I want to delete my account and know what happens to my data.

## Acceptance criteria

- [ ] A personal settings page (reachable from the user menu in every business) edits name,
      email (re-confirmation required before it takes effect) and password (current password
      required).
- [ ] Notification preferences for team emails (NTF-02) are linked from here once available.
- [ ] Users can see active sessions (device/browser, last active) and sign out of others.
- [ ] Account deletion requires password re-entry and explains consequences.
- [ ] Deletion is blocked while the user is the sole Owner of any business that has other
      members or data; the user is told how to transfer ownership or delete the business first.
- [ ] On deletion, memberships end, the user's personal data is removed or anonymized, and
      historic records show a neutral "former member" label.
- [ ] Email change and deletion send confirmation emails to the relevant addresses.
- [ ] Tests cover the sole-owner rule and anonymization.

## Out of scope

- Deleting a business (owner action) — covered by OPS-04 at launch; self-serve backlog.
- Two-factor authentication for business users (backlog).

## Open questions

- Should business deletion be self-serve for Owners at launch? Recommend operator-assisted
  until usage justifies building it.
