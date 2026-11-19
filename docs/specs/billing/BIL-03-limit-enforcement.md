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

- [x] At a configurable threshold (default 80%), Owners/Admins see a non-blocking notice with
      usage and reset date.
- [x] At the limit, sending a new quote is replaced by an explanation and upgrade prompt (Owners
      get an upgrade button; Admins are told to ask the Owner). Drafts can still be created and
      edited.
- [x] Client-facing flows always work regardless of plan state: viewing, approving and paying
      previously sent documents; visit pages; the request form (submissions still accepted).
- [x] Member limit: inviting beyond the plan's member limit shows an upgrade prompt; existing
      members are never removed automatically.
- [x] Feature switches (e.g. hiding "Powered by Shadetree") revert gracefully on downgrade; no
      data is deleted; over-limit content becomes read-only where relevant.
- [x] All prompts link to the upgrade flow (BIL-04); prompt copy is reviewed and consistent.
- [x] Tests cover thresholds, at-limit behavior per role, client flows unaffected, and downgrade.

## Out of scope

- Payment and plan change itself (BIL-04). Overage billing (not planned).

## Decisions

- A grace of one: at the limit, one more new quote can go out (with a warning) so nobody is
  blocked mid-conversation; then new quotes wait for the reset or a bigger plan.

## Implementation notes

- `Entitlements#quote_sending` answers `:ok`, `:approaching` (from `USAGE_WARNING_PERCENT`,
  default 80), `:at_limit` (the one extra left) or `:blocked`. Only a quote's first send counts
  and is checked (`Admin::QuoteSendsController#require_quote_allowance`, both email and link);
  resends and revisions of quotes already sent never count, and drafts always save.
- One notice (`admin/usage/_limit_notice`) on the quote builder, the send page (where Send and
  Get the link are disabled when blocked) and the dashboard: usage, the reset date, and
  "See plans" for owners (Settings → Plan, which BIL-04 turns into checkout) or "Ask <owner>"
  for others.
- Team size: at the limit the team page shows the same kind of prompt instead of the invite
  form (BIL-01 enforces it); members are never removed.
- Nothing client-facing checks entitlements: sent quotes and invoices stay viewable, approvable
  and payable, visit pages and the request form keep working (tested over the limit).
- A downgrade turns features off ("Powered by" returns) and deletes nothing. No content is
  over-limit today; later gated features (templates, automations, roles, locations) keep their
  data read-only.
