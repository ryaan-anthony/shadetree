---
id: OPS-03
title: Impersonation
domain: operator
milestone: M5
depends_on: [OPS-02, ACC-04]
---
# OPS-03 · Impersonation

> Requirements: [10-operator](../../plans/10-operator.md) R6, R7

## Summary

"I can't see the button" is solved fastest by seeing what the user sees. Let an operator view
the app as a specific member, safely: read-only by default, every session justified and
audited, impossible to mistake for normal use.

## User stories

- As an operator, I want to see exactly what an owner sees so that I can answer their question
  without a screen-share.
- As a business owner, I want platform staff to be unable to change my billing or password
  while helping me.

## Acceptance criteria

- [x] From a business page, an operator selects a member and enters a reason to start
      impersonating; the session starts in that business as that member.
- [x] A persistent, unmistakable banner shows who is being impersonated, by whom, read-only or
      write mode, and a Stop button; sessions time out automatically.
- [x] Read-only mode blocks all state-changing actions with a clear message.
- [x] Write mode requires an explicit switch with a second reason; even then, sensitive actions
      are always blocked: password/email changes, billing and plan changes, payment account
      connection, member role changes involving Owners, business deletion.
- [x] No emails or notifications are sent to clients as a side-effect of read-only browsing
      (e.g. previews don't count as client views).
- [x] Start, stop, mode changes and every write action during impersonation are recorded in the
      audit log; the business's activity (if a business log exists) shows that support accessed
      the account.
- [x] The operator's own identity is restored on stop; impersonation can't be nested.
- [x] Tests cover blocked actions in both modes, timeouts, audit records and banner presence.

## Out of scope

- Impersonating operators; client-link impersonation (operators can use staff preview).

## Decisions

- Owners aren't emailed; each visit is listed for Owners under "Shadetree support access" on
  the Team page (when, as whom, read-only or how many changes, how long), without naming the
  operator (recommendation accepted, 10-operator open question 1).
- Operators and the operator themself can't be viewed as. Sessions end after 15 minutes idle
  (as the console does) or an hour in all.

## Implementation notes

- `Impersonation` lives in the operator's own Warden session data, so signing out ends it (and
  is allowed: it records `ended: signed_out` first); ended sessions are on record, so an old
  cookie can't revive one. `ImpersonationSupport` makes `current_user` the member everywhere but
  `Ops::`. Each staff, account and invitation controller declares `impersonation :allowed`,
  `:read_only` or `:blocked` (per action, with `reads:` for POSTs that only search or preview);
  a test walks the routes for undeclared ones, and undeclared means read-only. Blocked in both
  modes: data downloads, invitations (sending and accepting), account settings and sign-in pages,
  switching or adding a business. Never changed even in write mode: plans, client erasure, test
  emails, Owners' roles, the business's email. Events recorded meanwhile read "… via Shadetree
  support" in histories (`Current.impersonator`).
- Browsing leaves no trace on the member: last active isn't touched, notifications opened stay
  unread, client link views aren't recorded, and legal re-acceptance isn't asked.
- Start needs a reason and a recent code; "Allow changes" a second reason and a recent code; Stop
  always works. Audited: `impersonation.started`, `changes_allowed`, `read_only`, `change`
  (every change: controller#action, method, path, status, where it led) and `ended` (stopped,
  signed out, timed out or access changed; minutes to its last request), tied by a session id.
- The banner (`layouts/_impersonation_banner`) is on every layout. Dev seeds: a past visit.
  Tests: `test/integration/ops/impersonation_test.rb`.
