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
- [ ] Ready-made recipes (quote follow-up, overdue invoice reminder, auto-invoice on
      completion, review request after payment) can be switched on in one step and edited.
- [x] Conditions are re-checked when the delay ends; actions that no longer apply are skipped
      and logged (e.g. no reminder once the quote is approved).
- [ ] Every run is logged on the business's automation page and on the affected record: what
      triggered it, what ran, what was skipped and why.
- [x] Safeguards: a client never receives the same automated message more than once per
      document. Rules can't trigger each other in loops. Automations pause for suspended
      businesses and respect bounce suppression.
- [x] Automations are a plan feature (BIL-01) with a limit on active rules per plan.
- [ ] Tests cover delays, condition re-checks, idempotency, loop prevention, logs and tenancy.

## Out of scope

- A visual flow builder, arbitrary branching, outbound webhooks or Zapier (backlog), and SMS
  actions until SMS exists.

## Decisions

- **Four recipes at launch** (recommendation accepted): quote follow-up, overdue invoice
  reminder, auto-invoice on completion, review request after payment.
- **Auto-create job on approval becomes a recipe** (recommendation accepted); until part 2
  moves it, the JOB-01 setting keeps working beside the "create a job" action.
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

Part 1 (the engine):
- `AutomationRule`: a trigger (`TRIGGERS`: request received, quote sent / viewed / approved /
  declined, job completed, visit booked, invoice sent / overdue, payment received), a delay (up
  to 90 days), conditions and actions (`ACTIONS`: email a template of the business's own,
  notify the team, create a job from the quote, create and send the job's invoice, tag the
  client), each checked against what the trigger is about. The plan limit
  `active_automations` counts rules switched on (Pro 10, Business unlimited).
- `Automation.trigger` is called by `ClientEvent` (after commit), `Job#complete!` and the hourly
  `AutomationsDueJob` (overdue invoices, and any due run a restart dropped). Each active rule
  gets one `AutomationRun` per record (unique), always run by `AutomationRunJob` (even with no
  delay), so a failing automation never breaks the request that triggered it; `trigger` reports
  errors rather than raising. The sweep handles each business on its own, so one failure
  doesn't stop the rest. Running re-checks the plan, the business, the rule and its conditions, then does
  each action in its own savepoint and logs the result ("done", "skipped" with why, "failed" with
  the error); anything unexpected marks the run failed rather than retrying it forever.
- Safeguards: events recorded while an automation acts (`Current.automation_run`, taken when the
  event is created, not when it commits) trigger nothing, so rules can't feed each other; a template goes to a client once per document
  (`AutomationDelivery`); runs wait while the business is suspended; plans without automations skip;
  `AutomationMailer` sends through the client mailer, so suppressed addresses aren't mailed.

Part 2: the automations page (rules, recipes, the log), and runs shown on each record.

## Open questions

- None.
