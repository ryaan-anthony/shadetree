---
id: OPS-02
title: Business directory
domain: operator
milestone: M5
depends_on: [OPS-01, BIL-01]
---
# OPS-02 · Business directory

> Requirements: [10-operator](../../plans/10-operator.md) R4, R5, R8

## Summary

Operators need to find any business quickly and understand its situation at a glance — who
owns it, what plan it's on, whether it's actually using the product, and any history with
support — before helping or making decisions.

## User stories

- As an operator answering a support email, I want to find the sender's business by email in
  seconds.
- As the founder, I want to see which new businesses are active and which stalled at setup.

## Acceptance criteria

- [ ] A searchable, paginated list of businesses by name, owner/member email, plan, status
      (active, trial, past due, suspended) and signup date range; sortable by signup and last
      activity.
- [ ] A business page shows: owner and members (role, last active), plan and subscription
      status, current-period usage vs limits, counts (clients, quotes sent, jobs, invoices,
      payments), onboarding checklist progress, payment-account connection status, signup and
      last activity dates, and recent billing history.
- [ ] Operators can add, edit and delete their own internal notes on a business; notes show
      author and time.
- [ ] A user lookup finds a person by email and lists their memberships.
- [ ] Viewing a business page is recorded in the audit log.
- [ ] The directory shows no client personal data (business-level aggregates only).
- [ ] Tests cover search, access control and audit entries.

## Out of scope

- Impersonation (OPS-03) and account actions (OPS-04). Platform-wide metrics dashboard
  (backlog).

## Open questions

- Should operator notes be visible to the business? Recommend no (internal only).
