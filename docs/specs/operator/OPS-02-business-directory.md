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

- [x] A searchable, paginated list of businesses by name, owner/member email, plan, status
      (active, trial, past due, suspended) and signup date range; sortable by signup and last
      activity.
- [ ] A business page shows: owner and members (role, last active), plan and subscription
      status, current-period usage vs limits, counts (clients, quotes sent, jobs, invoices,
      payments), onboarding checklist progress, payment-account connection status, signup and
      last activity dates, and recent billing history.
- [x] Operators can add, edit and delete their own internal notes on a business; notes show
      author and time.
- [x] A user lookup finds a person by email and lists their memberships.
- [x] Viewing a business page is recorded in the audit log.
- [x] The directory shows no client personal data (business-level aggregates only).
- [x] Tests cover search, access control and audit entries.

## Out of scope

- Impersonation (OPS-03) and account actions (OPS-04). Platform-wide metrics dashboard
  (backlog).

## Decisions

- Operator notes are internal only; the business never sees them (recommendation accepted).
- The business-page criterion stays unticked until PAY-03 (owner's decision; #117 stays
  open): the payment account reads "Not connected" until then. Trial and Past due statuses,
  the subscription and billing history came with BIL-04/05.

## Implementation notes

- `/ops/businesses` (`Ops::Directory`): name or any member's email (partial, case-insensitive),
  plan, status, signup dates (UTC); sorted by signup or last activity (the latest member
  activity); 25 a page. `/ops/businesses/:uid` (`Ops::BusinessSummary`) reads counts inside
  `Tenancy.with_business`, so no tenancy bypass, and shows no client names or details.
  Opening it writes `business.viewed` to the audit log.
- Notes (`OperatorNote`): platform data, not tenant-scoped; any operator adds one, only its
  author edits or deletes it (others get 404); added/edited/deleted are audited without the text.
- `/ops/users?email=`: people whose email contains the text (first 20), with memberships.
- Dev seeds: a note on the demo business. Tests: `test/integration/ops/business_directory_test.rb`,
  `operator_notes_test.rb`; `sign_in_operator` helper in `test/support/operator_helpers.rb`.
