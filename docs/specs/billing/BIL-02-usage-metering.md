---
id: BIL-02
title: Usage metering
domain: billing
milestone: M5
depends_on: [BIL-01, QTE-04]
---
# BIL-02 · Usage metering

> Requirements: [09-billing](../../plans/09-billing.md) R4, R5

## Summary

Count billable usage — quotes sent — accurately per business per billing period, and show it to
the owner plainly. Accuracy and transparency matter more than sophistication: owners must trust
the number they're charged on.

## User stories

- As an owner on the Free plan, I want to see "3 of 5 quotes sent this month" so that there are
  no surprises.
- As the operator, I want reliable usage numbers per business for support and pricing decisions.

## Acceptance criteria

- [x] Each billable event (first send of a quote, per QTE-04) is counted exactly once per
      business, even with retries, resends and concurrent requests.
- [x] Usage periods: calendar month (business time zone) for Free; the subscription's billing
      cycle for paid plans; the current period's usage and reset date are queryable.
- [x] Owners/Admins see current usage vs limit in Settings → Plan and in a compact indicator
      near the quote send action and on the dashboard summary (INS-01).
- [x] Historical usage per period is retained (at least 24 months) and visible to operators.
- [x] Changing plans mid-period keeps the period's usage and applies the new limit.
- [x] Usage counting does not slow down sending (measured).
- [x] Tests cover idempotency, period boundaries (time zones, month lengths), plan changes and
      tenancy.

## Out of scope

- Blocking at the limit (BIL-03). Reporting usage to the billing provider for metered charges
  (backlog — only needed if overage pricing is adopted).

## Decisions

- The billable metric is quotes sent: a quote's first send (QTE-04), once per quote however
  often it's resent or revised.
- No overage pricing: plan upgrades only.

## Implementation notes

- `UsageEvent` already records each quote's first send exactly once (a unique index on the
  subject). `UsagePeriod.for(business)` gives the period: the calendar month in the business's
  time zone on a free plan, or monthly from `businesses.billing_cycle_anchor` on a paid plan
  (BIL-04 sets it; an anchor on the 31st renews on the last day of shorter months). It answers
  `range`, `resets_on`, `used` (one count on the `(business, kind, occurred_at)` index) and
  `history` (as many periods back as asked; events are never deleted).
- `Entitlements#used(:quotes_sent)` counts the current period, so changing plan mid-period
  keeps the usage and applies the new limit.
- Shown on Settings → Plan (with the reset date), beside Send in the quote builder and on the
  send page for a quote's first send (not a revision's), and in the dashboard's summary ("3 of
  5", labelled month or billing period); only when the plan has a limit.
- Speed: the send path doesn't change (the usage event was already one insert in `mark_sent!`,
  QTE-04); the count is read only on pages, as one index-only query (a test checks one query).
- Operators: `bin/rails usage:history BUSINESS=<uid>` (24 periods).
- #289: usage is worded as what it is wherever it shows: "1 of your 5 free quotes this month", or
  "12 of your 30 Starter quotes this billing period".
