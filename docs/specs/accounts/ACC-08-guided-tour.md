---
id: ACC-08
title: Guided tour and first-time tips
domain: accounts
milestone: M6
depends_on: [ACC-05, ACC-04]
---
# ACC-08 · Guided tour and first-time tips

> Requirements: [02-accounts](../../plans/02-accounts.md) R15

## Summary

New owners aren't software people. When someone creates a business, a short tour shows them
where things live and what to do first, pointing at the real screens. After that, a one-line
tip appears the first time they open each main area. Everything can be skipped, and comes back
from Help.

## User stories

- As a new owner, I want a two-minute walk through the app, so I know where requests, quotes,
  the schedule and invoices live before I start.
- As a new owner, I want a short hint the first time I open the quote builder, so I don't have
  to guess how it works.
- As a technician joining a crew, I want to be shown just My day, not the whole office.
- As someone who knows what they're doing, I want to skip all of it in one click.

## Acceptance criteria

- [x] After creating a business, the owner is offered the tour ("Take a 2-minute tour" or "Skip").
      It has about six stops, each pointing at the real thing on screen: Home and its setup
      checklist, Requests, Quotes, Schedule, Invoices and Settings. Each stop says in a sentence
      or two what it's for and what to do first.
- [x] Each stop has Back, Next and "End tour". The last stop leads to the first unfinished
      checklist step. The tour never blocks the page underneath.
- [x] The tour fits the person's role. Technicians get a short version of My day and their visits
      only. Admins get the office stops without billing. Stops for things a role can't use are
      left out.
- [ ] First-time tips: the first visit to Requests, the quote builder, the send page, Schedule,
      Invoices, Services & prices and Settings shows one short, dismissible tip. A tip shows
      once per person per business, and doesn't show while the tour is running.
- [ ] Help offers "Take the tour again" and "Show tips again". Personal settings can turn tips
      off.
- [x] It works on phones (the tour becomes a bottom sheet that steps through the menu) and with
      the keyboard and screen readers (focus moves into each stop and back, Escape ends it). It
      respects reduced motion, and the axe check passes with it open.
- [ ] Stops and tips are written in the product's plain voice, from the person's point of view,
      with no jargon. Wording lives in one place so it's easy to edit.
- [x] Whether the tour was finished or skipped, and at which stop, is recorded per person for
      product measurement, without personal data, alongside ACC-05's time-to-first-quote.
- [ ] Tests cover the offer, role variants, skip and resume, the tips showing once, restarting
      from Help, keyboard use and mobile.

## Out of scope

- Videos, an in-app help centre or articles (backlog).
- Tours for operators (OPS).
- A third-party tour service that sends user data elsewhere.

## Decisions

- The tour is offered once on Home after the business is created: one click starts it, one
  skips it (owner, 2026-11-21).
- Invited Admins get the tips; the tour is available to them from Help (owner, 2026-11-21).
- The Quotes stop uses the sample quote (Q-SAMPLE) to show what clients see (owner, 2026-11-21).

## Implementation notes

- Built in-house (Stimulus, no tour library). Stops point at `data-tour="…"` attributes, never
  at position or copy; Home's checklist and the menu links carry them. Wording:
  `config/locales/guidance.en.yml`; which stops a role gets: `GuidedTour`.
- Only the person who creates a business is offered it (businesses that existed before aren't);
  technicians start theirs from their My day welcome ("Show me around"), everyone from Help.
- Per membership: `tour_status` (offered, started, finished, skipped), `tour_stop` (reached, or
  where it ended; "offer" when skipped there), offered and ended times. `bin/rails
  onboarding:tour` reports outcomes, where people stopped and the median time to first quote
  for each; counts only.
- Proposed, pending the owner: the first run's outcome is kept once it ends, and taking the
  tour again from Help only stamps `tour_replayed_at`. This keeps the measurement honest: a
  replay can't overwrite a skip, or turn a finished tour back into started.
- Support viewing as a member sees the tour but never records it (the endpoint is read-only
  under impersonation, and the page doesn't report moves).
- One non-modal dialog (`role=dialog`, `aria-modal=false`) moves between stops, saying what it
  points at; it takes focus at each, F6 moves between it and the target, Escape ends it, and
  focus goes back (or to the checklist step it leads to). No backdrop or focus trap. Below
  960px it's a bottom sheet the page and target scroll clear of, opening the menu for menu stops.
- Leaving the page ends the tour at that stop (recorded as ended there), except through its own
  sample-quote link: it resumes on return (this tab, 30 minutes; forgotten on sign-out).
- Dev seeds: `new@example.com` owns a brand-new business with the offer and checklist showing.
