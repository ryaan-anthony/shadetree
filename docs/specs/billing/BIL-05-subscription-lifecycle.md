---
id: BIL-05
title: Trials, failed payments & downgrades
domain: billing
milestone: M5
depends_on: [BIL-04, BIL-03]
---
# BIL-05 · Trials, failed payments & downgrades

> Requirements: [09-billing](../../plans/09-billing.md) R8, R11, R12

## Summary

Handle the edges of a subscription gracefully: an optional free trial of a paid plan, cards
that fail, and businesses that cancel or lapse. Owners should always know where they stand, and
nobody loses data because a card expired.

## User stories

- As a new owner, I want to try paid features without entering a card.
- As an owner whose card failed, I want a clear warning and time to fix it.
- As an owner who cancels, I want to keep my data and continue on Free.

## Acceptance criteria

- [ ] New businesses can start with a trial of a configured paid plan (length configurable,
      0 disables); trial status and days remaining are visible; reminders are emailed before it
      ends; at the end without payment the business moves to Free.
- [ ] When a renewal payment fails, Owners see a persistent banner with a link to update
      payment; the plan continues through a configurable grace period while the provider
      retries.
- [ ] If the subscription ends (canceled or unpaid after grace), the business moves to Free at
      the end of the paid period; Owners are emailed; limits and features follow BIL-03
      downgrade rules; nothing is deleted.
- [ ] Reactivating (paying again) restores the paid plan immediately.
- [ ] All transitions are driven by provider events or scheduled checks, are idempotent, and are
      recorded in a per-business billing history visible to operators.
- [ ] Tests cover trial expiry, grace, downgrade at period end, reactivation and duplicate
      events.

## Follow-ups

- Add Trial / Past due / Suspended / payment-account status and billing history to the OPS-02
  directory and business page (OPS-02 shows Active and Closed only until then).

## Out of scope

- Dunning emails (provider handles retries and payment-failure emails).
- Win-back campaigns (backlog).

## Open questions

- Trial design: 14-day Pro trial without card (recommended) vs no trial (Free is the trial).
- Grace period length — recommend 7 days after first failure.
