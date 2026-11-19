---
id: NTF-04
title: Workflow automations
domain: notifications
milestone: M5
depends_on: [NTF-02, NTF-03, QTE-06, JOB-02, PAY-02]
---
# NTF-04 · Workflow automations

> Requirements: [08-notifications](../../plans/08-notifications.md) R12–R15

## Summary

Follow-ups are where small businesses lose money: the unanswered quote, the forgotten invoice,
the review never requested. Let a business turn on automations that react to events in the core
flow (quote → job → invoice) — after an optional delay and only if conditions still hold — by
sending a message, notifying the team or moving work forward. Start from ready-made recipes;
build custom rules from a fixed list of triggers, conditions and actions.

## User stories

- As an owner, I want unapproved quotes to get a friendly reminder after 3 days.
- As an owner, I want an invoice created and sent automatically when a job is completed.
- As an owner, I want to be told when a quote I sent a week ago still hasn't been viewed.

## Acceptance criteria

- [x] Triggers come from a documented catalog of core-flow events: request received, quote
      sent, viewed, approved or declined, job completed, visit scheduled, invoice sent, invoice
      overdue, payment received.
- [x] A rule is: a trigger, optional delay (hours/days), optional conditions (e.g. document
      still unapproved or unpaid, total above an amount, client tag, location), and one or more
      actions.
- [x] Actions come from a fixed catalog: send a client message template (NTF-03), notify team
      members or roles, create a job from an approved quote, create and send an invoice from a
      completed job, add a client tag.
- [x] Ready-made recipes (quote follow-up, overdue invoice reminder, auto-invoice on
      completion, review request after payment) can be switched on in one step and edited.
- [x] Conditions are re-checked when the delay ends; actions that no longer apply are skipped
      and logged (e.g. no reminder once the quote is approved).
- [x] Every run is logged on the business's automation page and on the affected record: what
      triggered it, what ran, what was skipped and why.
- [x] Safeguards: a client never receives the same automated message more than once per
      document. Rules can't trigger each other in loops. Automations pause for suspended
      businesses and respect bounce suppression.
- [x] Automations are a plan feature (BIL-01) with a limit on active rules per plan.
- [x] Tests cover delays, condition re-checks, idempotency, loop prevention, logs and tenancy.

## Out of scope

- A visual flow builder, arbitrary branching, outbound webhooks or Zapier (backlog), and SMS
  actions until SMS exists.

## Decisions

- **Four recipes at launch** (recommendation accepted): quote follow-up, overdue invoice
  reminder, auto-invoice on completion, review request after payment.
- **Auto-create job on approval becomes a recipe** (accepted), beside the four. The JOB-01
  setting stays for plans without automations; with both on there's still one job (unique
  index). Retiring the setting on paid plans is the owner's call.
- **The location condition waits for CAT-07**; the conditions today are still open, total at
  least, and client tag.
- **"Notify the team" goes to everyone with a permission** (running the office, or
  scheduling), so custom roles (ACC-07) are covered without naming roles.
- **An overdue rule chases invoices that fall due after it's made**, not every old invoice the
  moment it's switched on.
- **Logs and notices name the record (Q-1042), never the client**, so client erasure (INS-02)
  has nothing to scrub there; runs for an erased client are skipped.
- **While a business is suspended**, new events start nothing and waiting runs stay waiting;
  they go ahead (conditions re-checked) once it's active again.

## Implementation notes

- Engine: `AutomationRule` (`TRIGGERS`, `CONDITIONS`, `ACTIONS`, each listing the subjects it
  fits; delay up to 90 days; plan limit `active_automations`: Pro 10, Business unlimited).
  `Automation.trigger` is called by `ClientEvent` (after commit), `Job#complete!` and the hourly
  `AutomationsDueJob`, which handles overdue invoices and dropped runs, one business at a time.
  - Each rule gets one `AutomationRun` per record. Runs always go through `AutomationRunJob`,
    so a failure never breaks the triggering request; `trigger` reports errors, never raises.
  - A run re-checks the plan, rule and conditions, then does each action in a savepoint and logs
    "done", "skipped" with why, or "failed". Anything unexpected marks the run failed.
- Safeguards: events recorded while an automation acts trigger nothing (the flag is taken when
  the event is created). A template reaches a client once per document (`AutomationDelivery`).
  Runs wait while the business is suspended, and `AutomationMailer` respects suppression.
- Pages: Settings → Automations (`Admin::AutomationsController`, `business_settings`) lists rules
  described in a sentence (`automation_summary`) with Turn on / off, the recipes
  (`AutomationRecipe`, which brings its template once) and recent activity. The form
  (`automation_form_controller.js`) shows only what fits the trigger. Quotes, invoices (with
  their payments) and jobs show their runs. Without the feature, the history stays read-only.
- Dev seeds: `AutomationRecipe.install!("quote_follow_up", by: user)` inside the business.

## Open questions

- None.
