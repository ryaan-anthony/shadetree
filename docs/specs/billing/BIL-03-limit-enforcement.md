---
id: BIL-03
title: Limit enforcement & upgrade prompts
domain: billing
milestone: M5
depends_on: [BIL-02]
---
# BIL-03 · Limit enforcement & upgrade prompts

> Requirements: [09-billing](../../plans/09-billing.md) R6, R7, R8; vision principle 6

## Summary

When a business reaches a plan limit, explain it kindly and offer an upgrade at the moment it
matters — without ever breaking something a client is in the middle of. Honest, predictable
limits are part of the brand.

## User stories

- As an owner nearing my limit, I want a heads-up before I'm blocked.
- As an owner at my limit, I want to understand what happened and upgrade in one step.
- As a client, I never want to see an error because the business hit a plan limit.

## Acceptance criteria

- [ ] At a configurable threshold (default 80%), Owners/Admins see a non-blocking notice with
      usage and reset date.
- [ ] At the limit, sending a new quote is replaced by an explanation and upgrade prompt (Owners
      get an upgrade button; Admins are told to ask the Owner). Drafts can still be created and
      edited.
- [ ] Client-facing flows always work regardless of plan state: viewing, approving and paying
      previously sent documents; visit pages; the request form (submissions still accepted).
- [ ] Member limit: inviting beyond the plan's member limit shows an upgrade prompt; existing
      members are never removed automatically.
- [ ] Feature switches (e.g. hiding "Powered by Shadetree") revert gracefully on downgrade; no
      data is deleted; over-limit content becomes read-only where relevant.
- [ ] All prompts link to the upgrade flow (BIL-04); prompt copy is reviewed and consistent.
- [ ] Tests cover thresholds, at-limit behavior per role, client flows unaffected, and downgrade.

## Out of scope

- Payment and plan change itself (BIL-04). Overage billing (not planned).

## Open questions

- Grace allowance: allow one or two sends over the limit with a warning before blocking?
  Recommend a small grace (e.g. +1) to avoid blocking mid-conversation.
