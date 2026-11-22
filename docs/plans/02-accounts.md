# 02 · Accounts & team

## Purpose

Let people sign up, sign in, create one or more businesses, bring in their team with the right
level of access, and reach "first quote sent" as quickly as possible.

## Current state

- Email/password sign-up with email confirmation, sign-in, password reset (Devise).
- A user can own several businesses and switch between them; a membership join exists with a
  free-text role (`member` default).
- A second, overlapping model set exists for staff (`staff_members`, `business_roles` with JSON
  permissions, `staff_roles`) that is not wired to any UI.
- `account_tier` lives on the user.
- A business setup flow with tabs (details, hours, branding) exists.

## Users

Owner, Admin, Technician (see vision glossary). Operators are covered in `10-operator`.

## Requirements

### Identity
- **R1** Sign up with name, email, password; email must be confirmed before a business can send
  anything to clients (sign-in itself may be allowed before confirmation — see open questions).
- **R2** Sign in, sign out, "remember me", password reset, lockout after repeated failures.
- **R3** A user can change their name, email (re-confirmed), and password, and delete their
  account (blocked while they are the sole owner of a business with data).
- **R4** Sessions can be revoked ("sign out everywhere").

### Businesses
- **R5** After sign-up, the user creates a business (name and industry are the only required
  fields) and becomes its Owner.
- **R6** A user can belong to multiple businesses with different roles and switch between them;
  the current business is always visible in the app chrome.
- **R7** A business always has at least one Owner. Ownership can be transferred.

### Team
- **R8** Owners and Admins invite people by email with a role. Invitations expire, can be
  resent and revoked. Invitees without an account create one during acceptance.
- **R9** Members can be deactivated (lose access immediately, history kept) and reactivated.
- **R10** Fixed roles:

| Capability | Permission (code) | Owner | Admin | Technician |
| --- | --- | --- | --- | --- |
| Billing, plan, delete business, transfer ownership | `billing`, `manage_owners` | ✔ | | |
| Manage team & roles (except Owners) | `manage_team` | ✔ | ✔ | |
| Business settings, catalog, taxes | `business_settings` | ✔ | ✔ | |
| Clients, requests, quotes, jobs, invoices, payments (all) | `office` | ✔ | ✔ | |
| Schedule and assign visits | `schedule` | ✔ | ✔ | |
| See own assigned visits, their client contact & property, add notes/photos, mark complete | `field_work` | ✔ | ✔ | ✔ |
| Data export | `export_data` | ✔ | ✔ | |

The **Permission** column names the code permissions in `app/models/permissions.rb`. This
table is the source of truth: change both together.

- **R11** Role checks are enforced server-side for every action and covered by tests.
  Authorization is expressed as named permissions (the rows of the table above) mapped to
  roles, so custom roles can be added without changing features.
- **R14** Owners can define custom roles from the permission catalog, alongside the built-in
  roles (paid plans). A few permissions stay Owner-only.

### Onboarding
- **R12** A new owner is guided through: business basics → choose industry (seeds starter
  services) → branding (optional) → create first client and quote. Every step is skippable and
  resumable; progress is visible until complete.
- **R13** A demo/sample mode lets a new owner see a pre-filled quote before entering real data
  (may be satisfied by sample data seeded and clearly labeled).
- **R15** New owners get a short, skippable tour of the real screens when they create a
  business, and a one-line tip the first time they open each main area. Both are role-aware and
  can be restarted from Help (owner request, 2026-11-21).

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Three built-in roles at launch; custom roles built from a fixed permission catalog in M5. | Built-in roles cover 1–10 person crews; the permission catalog keeps custom roles cheap to add later. Replaces the free-form JSON permissions. |
| D2 | One membership concept for every person in a business. | The separate staff model duplicated memberships. |
| D3 | Plan/tier belongs to the business, not the user. | A user may be in several businesses on different plans. |
| D4 | Keep email + password at launch; passwordless is backlog. | Already built; magic links add email deliverability dependency on sign-in. |
| D5 | Technicians are not counted as paid seats by default. | Pricing is usage-based (see 09-billing). |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [ACC-01](../specs/accounts/ACC-01-sign-up-sign-in.md) | Sign up & sign in | M1 | PLT-05, PLT-07 |
| [ACC-02](../specs/accounts/ACC-02-businesses-and-switching.md) | Businesses & switching | M1 | ACC-01, PLT-06 |
| [ACC-03](../specs/accounts/ACC-03-team-invitations.md) | Team invitations & membership | M1 | ACC-02 |
| [ACC-04](../specs/accounts/ACC-04-roles-permissions.md) | Roles & permissions | M1 | ACC-02 |
| [ACC-05](../specs/accounts/ACC-05-onboarding.md) | Guided onboarding | M2 | CAT-01, CAT-05, QTE-03, QTE-04 |
| [ACC-06](../specs/accounts/ACC-06-account-settings.md) | Account settings & deletion | M5 | ACC-01 |
| [ACC-07](../specs/accounts/ACC-07-custom-roles.md) | Custom roles | M5 | ACC-04, BIL-01 |
| [ACC-08](../specs/accounts/ACC-08-guided-tour.md) | Guided tour and first-time tips | M6 | ACC-05, ACC-04 |

## Backlog (M6)

- Passwordless magic-link sign-in.
- Sign in with Google / Apple.
- Two-factor authentication for business owners (required for operators already — OPS-01).
- Ownership transfer UI (R7 is enforced at launch; transfer can be done by operators).

## Open questions

1. Can an unconfirmed user sign in and start setting up (lower friction), with client-facing
   sends blocked until confirmed? Recommend **yes**.
2. Should Technicians be able to create quotes in the field? Common in trades. Recommend a
   per-business toggle in M6; launch with Admin+ only.
3. Is there a cap on members on the Free plan? Owned by `09-billing`.
4. Does a deactivated member's name stay on historic records (quotes, visits)? Recommend yes.
