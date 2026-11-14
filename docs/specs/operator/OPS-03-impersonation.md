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

- [ ] From a business page, an operator selects a member and enters a reason to start
      impersonating; the session starts in that business as that member.
- [ ] A persistent, unmistakable banner shows who is being impersonated, by whom, read-only or
      write mode, and a Stop button; sessions time out automatically.
- [ ] Read-only mode blocks all state-changing actions with a clear message.
- [ ] Write mode requires an explicit switch with a second reason; even then, sensitive actions
      are always blocked: password/email changes, billing and plan changes, payment account
      connection, member role changes involving Owners, business deletion.
- [ ] No emails or notifications are sent to clients as a side-effect of read-only browsing
      (e.g. previews don't count as client views).
- [ ] Start, stop, mode changes and every write action during impersonation are recorded in the
      audit log; the business's activity (if a business log exists) shows that support accessed
      the account.
- [ ] The operator's own identity is restored on stop; impersonation can't be nested.
- [ ] Tests cover blocked actions in both modes, timeouts, audit records and banner presence.

## Out of scope

- Impersonating operators; client-link impersonation (operators can use staff preview).

## Open questions

- Notify the business owner by email when support accesses the account? Recommend not by email;
  record it in an activity entry visible to Owners (10-operator open question 1).
