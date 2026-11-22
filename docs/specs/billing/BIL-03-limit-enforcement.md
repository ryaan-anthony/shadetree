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
- [x] All prompts link to the upgrade flow — Settings → Plan for now; BIL-04 turns that page into checkout. Prompt copy is reviewed and consistent.
- [x] Tests cover thresholds, at-limit behavior per role, client flows unaffected, and downgrade.

## Out of scope

- Payment and plan change itself (BIL-04). Overage billing (not planned).

## Decisions

- No grace send at the limit (owner, 2026-11-22): once the plan's quotes are used, new quotes
  wait for the reset or a bigger plan. This replaces the earlier grace of one extra send.
- Resends and revisions of quotes already sent still go out at or over the limit and never
  count; the owner declined a guard on revisions (2026-11-22).

## Implementation notes

- `Entitlements#quote_sending` answers `:ok`, `:approaching` (from `USAGE_WARNING_PERCENT`,
  default 80, and always when one is left, so limits of 1–4 still warn before the block) or
  `:blocked` (at or over the limit; with no grace there's no separate "at the limit" state). Only a quote's first send counts
  and is checked (`Admin::QuoteSendsController#require_quote_allowance`, both email and link);
  resends and revisions of quotes already sent never count, and drafts always save.
- One notice (`admin/usage/_limit_notice`) on the quote builder, the send page (where the send
  options give way to the notice and a "Back to the quote" button when blocked) and the dashboard: usage, the reset date, and
  "See plans" for anyone who can manage billing (Settings → Plan, which BIL-04 turns into checkout) or "Ask <owner>"
  for others. Approaching, it says how many are left ("You can send 1 more"); blocked, it gives
  the real count when a downgrade left the business over the limit.
- The notice's plan link deliberately follows the billing permission (who can change the plan),
  not business settings as BIL-06's meter does: the notice is an upgrade prompt, the meter a
  view of usage.
- Team size: at the limit the team page shows the same kind of prompt instead of the invite
  form (BIL-01 enforces it); members are never removed.
- Nothing client-facing checks entitlements: sent quotes and invoices stay viewable, approvable
  and payable, and the request form keeps working (tested over the limit).
- The count is claimed inside the send transaction under a row lock on the business, so two
  first sends at the boundary can't both take the last one.
- A downgrade turns features off ("Powered by" returns) and deletes nothing. No content is
  over-limit today; later gated features (templates, automations, roles, locations) keep their
  data read-only.
