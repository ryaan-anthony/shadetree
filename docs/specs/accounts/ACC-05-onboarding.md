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

- [x] After creating a business, the owner sees a setup checklist: business details, add starter
      services (from industry preset), branding (optional), add a client, create and send a
      first quote. Completed steps tick automatically based on real data.
      *#289: now services, a client, the first quote and online payments (see Decisions).*
- [x] Each step deep-links into the real feature (no duplicate onboarding-only forms) and
      returns to the checklist. *Sending by link stays on the page with the link to copy.*
- [x] The checklist is visible on the dashboard until complete or dismissed; progress persists.
      *Finishing is remembered; each Owner or Admin can hide it for themselves and show it again.*
- [x] Choosing an industry offers to add that industry's starter services in one action.
- [x] A "preview a sample quote" action shows a realistic quote in the client-facing view using
      the business's branding, without creating real client data or counting toward usage.
- [x] Time from sign-up to first quote sent is measured (as a product metric, no PII).
      *`businesses.first_quote_sent_at`, from the business's setup (backfilled);
      `bin/rails onboarding:time_to_first_quote` summarizes it.*
- [x] The existing step-based setup flow is replaced; its onboarding fields are migrated or
      removed. *`onboarding_step` is ignored now and dropped in a later migration; `onboarded_at`
      means the checklist was finished.*

## Out of scope

- Product tours and tips (ACC-08). Importing clients during onboarding (CLI-06 may add a link later).

## Open questions

- ~~Should invited Admins/Technicians see a short role-specific welcome instead?~~ Technicians
  get a one-screen welcome on the dashboard, pointing to their visits (which arrive with M3).

## Decisions

- #289, 2026-11-22: the checklist is four steps on Home: add services and prices, add a client,
  send your first quote, get paid online (Stripe). The business details a quote needs open first
  from the quote step; branding moved out of the checklist (it's in Settings, and ACC-08's tour
  shows it). It stays until all four are done or the member hides it.

## Implementation notes

- #289: why staging showed no checklist: it's remembered as finished (`onboarded_at`) once its
  steps are done, and that business had already sent a quote. With the payments step, a new
  business keeps it until Stripe is set up. `/admin/setup` (a guessed address) goes to it on Home.
- It has a progress bar, "Hide" per member, and ticks from real data. ACC-08's tour relies on
  `data-tour="checklist"` on the card and `id="setup-<key>"` on each step: keep both.
