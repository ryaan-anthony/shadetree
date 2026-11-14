# 0012. Keep Devise for authentication

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** ACC-01, ACC-03, ACC-06, OPS-01, PLT-04

## Context

Sign-up, confirmation, sign-in, lockout and password reset run on Devise 4.9, with custom
controllers and views. Two Devise advisories are fixed only in Devise 5, which PLT-04 adopts.
Rails 8 ships an authentication generator as an alternative. Upcoming specs need invitations
(ACC-03), session revocation (ACC-01, ACC-06) and operator two-factor authentication (OPS-01).

## Options considered

1. **Migrate to the Rails 8 authentication generator.** No dependency and plain code we own.
   But confirmation, lockout and invitations would all be ours to build and keep secure, and
   existing flows would need rewriting.
2. **Keep Devise, upgrade to 5.x** in PLT-04, and add focused extensions where specs need them
   (invitations, two-factor authentication for operators).

## Decision

**Keep Devise** and upgrade it to 5.x in PLT-04. Use its modules for confirmation, lockout and
remember-me. Add invitations (ACC-03) and operator two-factor authentication (OPS-01) through
well-maintained Devise extensions or small custom code, each chosen in its own spec.

## Consequences

- Existing flows and tests keep working; the security fixes arrive with the 5.x upgrade.
- Devise's conventions shape the auth controllers. Customizations stay in the existing
  `Users::*` controllers.
- **Cost:** none.
