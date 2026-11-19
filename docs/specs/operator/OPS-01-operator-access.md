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

- [x] Operator access is a distinct grant, independent of business memberships; the first
      operator is created by a console command; operators can grant/revoke others; operators
      cannot revoke themselves if they are the last one.
- [x] Operators must enroll in and use two-factor authentication (authenticator app) to enter
      the console; recovery codes are provided.
- [x] The console lives in its own area with its own layout, is excluded from indexing, and
      returns "not found" to non-operators.
- [x] Operator console sessions expire after a short idle period and require re-authentication
      for sensitive actions.
- [x] An audit log records operator actions with operator, action, target business/user, reason
      where required, time, and request metadata; entries cannot be edited or deleted through
      the app.
- [x] The console shows the audit log with filters (operator, action, business, date).
- [x] A shared way to record audited actions is available to OPS-02..04 and other specs.
- [x] Tests cover access denial, 2FA enforcement, session expiry and audit immutability.

## Out of scope

- Business directory, impersonation and account actions (OPS-02..04).
- Multiple operator roles (backlog).

## Decisions

- Hand-built console ([ADR 0019](../../adr/0019-hand-built-operator-console.md)).
- No IP or VPN restriction at launch.

## Implementation notes

- `Operator` is a grant on a user (revocable, never the last one). The first comes from
  `bin/rails ops:grant EMAIL=…`; operators grant and revoke others in the console.
- Two-factor: authenticator-app codes (`Totp`, RFC 6238, no new dependency), the secret stored
  encrypted with a key derived from `secret_key_base`; each code works once; ten recovery codes,
  stored as HMAC digests, each used up.
- `/ops` (`Ops::` controllers, the `ops` layout): non-operators get 404; `noindex` and
  `no-store`. A code is needed every session (kept in the user's Warden session, so signing out
  ends it); 15 minutes idle ends it; granting or revoking needs a code from the last 5 minutes.
- `AuditEntry.record!(operator:, action:, business:, user:, reason:, request:, **data)` is the
  shared recorder (IP, browser, request id). Entries are read-only in the app, and a database
  trigger refuses UPDATE and DELETE (added by the migration and by every schema load,
  `lib/tasks/audit_log.rake`). The log is filterable by operator, action, business and dates.
