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

- [x] A personal settings page (reachable from the user menu in every business) edits name,
      email (re-confirmation required before it takes effect) and password (current password
      required).
- [x] Notification preferences for team emails (NTF-02) are linked from here once available.
- [x] Users can see active sessions (device/browser, last active) and sign out of others.
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

## Decisions

- **Business deletion stays operator-assisted at launch** (owner accepted the recommendation, M5
  planning); account deletion is self-serve (owner's request).
- **Signing out one browser also ends remember-me on every browser.** Devise's remember-me is
  per account, not per browser, so it's the only way the signed-out browser can't sign itself
  back in. Other browsers stay signed in until they're closed; the confirm says so.

## Implementation notes

Part 1 (settings page, sessions):
- The account page (Devise's edit registration, now in the plain app layout) already edited
  name, email (reconfirmed) and password (current password needed); it's linked from the user
  menu in every business. It now links team email choices (NTF-02) and lists where you're signed
  in.
- `UserSession` (config/initializers/user_sessions.rb): each sign-in starts one; the browser
  keeps "id:secret" in its session (only a digest is stored); each request checks it's active
  and notes activity at most every 5 minutes; signing out ends it. Listed: active in the last 30
  days, as "Chrome on Mac · last active … · IP · signed in …"; deleted after 90 days quiet.
- Signing out another browser (`Users::BrowserSessionsController`) ends it on its next request
  ("signed out from another device"); "Sign out of all other browsers" and a new password end
  every other session too.
