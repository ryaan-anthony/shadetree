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

- [ ] Each billable event (first send of a quote, per QTE-04) is counted exactly once per
      business, even with retries, resends and concurrent requests.
- [ ] Usage periods: calendar month (business time zone) for Free; the subscription's billing
      cycle for paid plans; the current period's usage and reset date are queryable.
- [ ] Owners/Admins see current usage vs limit in Settings → Plan and in a compact indicator
      near the quote send action and on the dashboard summary (INS-01).
- [ ] Historical usage per period is retained (at least 24 months) and visible to operators.
- [ ] Changing plans mid-period keeps the period's usage and applies the new limit.
- [ ] Usage counting does not slow down sending (measured).
- [ ] Tests cover idempotency, period boundaries (time zones, month lengths), plan changes and
      tenancy.

## Out of scope

- Blocking at the limit (BIL-03). Reporting usage to the billing provider for metered charges
  (backlog — only needed if overage pricing is adopted).

## Open questions

- **(blocking)** Confirm the billable metric is "quotes sent" (G3).
- Is there overage pricing (pay per extra quote) or only plan upgrades? Recommend upgrades only.
