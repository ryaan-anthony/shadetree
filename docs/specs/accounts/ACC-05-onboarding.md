---
id: ACC-05
title: Guided onboarding
domain: accounts
milestone: M2
depends_on: [CAT-01, CAT-05, QTE-03, QTE-04]
---
# ACC-05 · Guided onboarding

> Requirements: [02-accounts](../../plans/02-accounts.md) R12, R13; vision principle 1

## Summary

Our differentiator is time-to-value: a new owner should send a real quote within ten minutes
of signing up. Guide them through the few things that matter — business basics, industry
starter services, optional branding, and their first quote — with every step skippable.

## User stories

- As a new owner, I want a short checklist that gets me to my first sent quote so that I see
  the value before I invest more time.
- As a busy owner, I want to skip setup and come back later without losing progress.
- As a skeptical owner, I want to see what a quote looks like to my client before entering real
  data.

## Acceptance criteria

- [ ] After creating a business, the owner sees a setup checklist: business details, add starter
      services (from industry preset), branding (optional), add a client, create and send a
      first quote. Completed steps tick automatically based on real data.
- [ ] Each step deep-links into the real feature (no duplicate onboarding-only forms) and
      returns to the checklist.
- [ ] The checklist is visible on the dashboard until complete or dismissed; progress persists.
- [ ] Choosing an industry offers to add that industry's starter services in one action.
- [ ] A "preview a sample quote" action shows a realistic quote in the client-facing view using
      the business's branding, without creating real client data or counting toward usage.
- [ ] Time from sign-up to first quote sent is measured (as a product metric, no PII).
- [ ] The existing step-based setup flow is replaced; its onboarding fields are migrated or
      removed.

## Out of scope

- Product tours/tooltips. Importing clients during onboarding (CLI-06 may add a link later).

## Open questions

- Should invited Admins/Technicians see a short role-specific welcome instead? Recommend a
  one-screen welcome for Technicians pointing to "My day".
