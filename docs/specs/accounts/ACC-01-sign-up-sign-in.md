---
id: ACC-01
title: Sign up & sign in
domain: accounts
milestone: M1
depends_on: [PLT-05, PLT-07]
---
# ACC-01 · Sign up & sign in

> Requirements: [02-accounts](../../plans/02-accounts.md) R1, R2, R4

## Summary

Basic sign-up, confirmation, sign-in and password reset already exist. Bring them up to the new
UI foundation and product principles: minimal friction to get started, safe defaults, and
clear states for unconfirmed accounts.

## User stories

- As a prospective owner, I want to sign up with just my name, email and password so that I can
  try Shadetree immediately.
- As a returning user, I want to sign in quickly and stay signed in on my phone.
- As a user who forgot my password, I want to reset it from my email.

## Acceptance criteria

- [ ] Sign-up asks only for name, email and password (with strength guidance) and acceptance of
      the terms; it then lands the user in business creation (ACC-02).
- [ ] A confirmation email is sent; unconfirmed users can sign in and set up, but see a
      persistent "confirm your email" banner with resend, and cannot send anything to clients
      until confirmed (enforced where sending happens).
- [ ] Sign-in supports "remember me"; repeated failures trigger a temporary lockout with an
      unlock path; messages don't reveal whether an email exists.
- [ ] Password reset and change work end-to-end with expiring tokens.
- [ ] "Sign out of all devices" invalidates other sessions.
- [ ] All auth screens use the public layout, work at 360 px, and meet accessibility standards.
- [ ] Auth emails use the platform email layout (pre-NTF-01 a plain branded layout is fine).
- [ ] Existing auth tests are updated; new tests cover the unconfirmed-user restrictions.

## Out of scope

- Magic-link and social sign-in (backlog). Operator 2FA (OPS-01). Account deletion (ACC-06).

## Open questions

- ~~Confirm that unconfirmed users may sign in?~~ Resolved: yes. They can set up but can't send
  to clients until confirmed (`ConfirmedSender`).
- ~~Should sign-up capture the business name on the same screen?~~ Resolved: no. Sign-up stays
  identical for invitees (ACC-03), and business creation is the very next screen (ACC-02).
