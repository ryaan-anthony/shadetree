---
id: OPS-01
title: Operator access & audit log
domain: operator
milestone: M5
depends_on: [ACC-01, PLT-05]
---
# OPS-01 · Operator access & audit log

> Requirements: [10-operator](../../plans/10-operator.md) R1, R2, R3, R13

## Summary

Create the secure front door to the operator console: a separate, strongly authenticated class
of access for the people who run Shadetree, and an append-only audit log that every later
operator action writes to.

## User stories

- As the founder, I want to grant console access only to people I trust, protected by 2FA.
- As a business owner, I want confidence that platform staff actions on my account are recorded.

## Acceptance criteria

- [ ] Operator access is a distinct grant, independent of business memberships; the first
      operator is created by a console command; operators can grant/revoke others; operators
      cannot revoke themselves if they are the last one.
- [ ] Operators must enroll in and use two-factor authentication (authenticator app) to enter
      the console; recovery codes are provided.
- [ ] The console lives in its own area with its own layout, is excluded from indexing, and
      returns "not found" to non-operators.
- [ ] Operator console sessions expire after a short idle period and require re-authentication
      for sensitive actions.
- [ ] An audit log records operator actions with operator, action, target business/user, reason
      where required, time, and request metadata; entries cannot be edited or deleted through
      the app.
- [ ] The console shows the audit log with filters (operator, action, business, date).
- [ ] A shared way to record audited actions is available to OPS-02..04 and other specs.
- [ ] Tests cover access denial, 2FA enforcement, session expiry and audit immutability.

## Out of scope

- Business directory, impersonation and account actions (OPS-02..04).
- Multiple operator roles (backlog).

## Open questions

- Admin framework vs hand-built console — ADR (10-operator open question 3).
- Should operator access also be restricted by IP/VPN? Recommend not at launch.
