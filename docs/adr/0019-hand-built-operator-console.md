# 0019. Hand-built operator console

- **Status:** Accepted
- **Date:** 2026-11-19
- **Specs:** OPS-01, OPS-02, OPS-03, OPS-04, OPS-05

## Context

The people who run Shadetree need a console: find a business, see its plan and usage, act on
accounts, step in for support, and answer tickets, with every action audited. It has a handful
of screens and one or two operators at launch. 10-operator open question 3 asked whether to
use an admin framework or build it.

## Options considered

1. **An admin framework** (ActiveAdmin, Avo, Administrate): CRUD screens for every model for
   free. Pros: fast for table browsing. Cons: generic CRUD over every model is the opposite of
   what we want (operators should act through a few audited, purpose-built actions, never edit
   rows); another dependency and styling system; its authentication and authorization have to
   be bent to fit two-factor, idle expiry and the audit log.
2. **Hand-built in the app**: a `/ops` namespace with its own layout, built with the same
   components, tenancy helpers and tests as the rest of the app. Pros: only the screens and
   actions we choose exist, each audited; no new dependency; looks and behaves like the
   product. Cons: each screen is written by hand.

## Decision

Build the console by hand under `/ops` (`Ops::` controllers, the `ops` layout). Operators are a
grant on a user (`Operator`), separate from business memberships, and must use two-factor
(authenticator-app codes, verified in the app with no new dependency). Every action writes to
the append-only `AuditEntry` log through `AuditEntry.record!`.

## Consequences

- Each later operator feature (directory, impersonation, account actions, tickets) is a small,
  explicit set of screens, audited by construction.
- No bulk row editing: data fixes stay in the Rails console, run by an engineer.
- **Two-factor is built in** (RFC 6238 in `Totp`, ~40 lines, checked against the RFC's test
  vectors) rather than adding `rotp`; the QR code uses `rqrcode`, already a dependency.
- **The two-factor secrets and recovery-code digests are keyed from `secret_key_base`.**
  Rotating it makes every operator set up two-factor again (`bin/rails ops:reset_two_factor`
  for each, or they'll see setup on their next visit once the secret no longer decrypts).
- **The audit log's append-only triggers aren't in `schema.rb`**, which can't hold them. The
  migration creates them, and `lib/tasks/audit_log.rake` adds them after `db:prepare`,
  `db:schema:load` and the test schema load; the console's home warns if they're missing. A
  move to `structure.sql` would remove this workaround at the cost of the tooling built around
  `schema.rb`.
- **Cost:** none.
