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

- [ ] Triggers come from a documented catalog of core-flow events: request received, quote
      sent, viewed, approved or declined, job completed, visit scheduled, invoice sent, invoice
      overdue, payment received.
- [ ] A rule is: a trigger, optional delay (hours/days), optional conditions (e.g. document
      still unapproved or unpaid, total above an amount, client tag, location), and one or more
      actions.
- [ ] Actions come from a fixed catalog: send a client message template (NTF-03), notify team
      members or roles, create a job from an approved quote, create and send an invoice from a
      completed job, add a client tag.
- [ ] Ready-made recipes (quote follow-up, overdue invoice reminder, auto-invoice on
      completion, review request after payment) can be switched on in one step and edited.
- [ ] Conditions are re-checked when the delay ends; actions that no longer apply are skipped
      and logged (e.g. no reminder once the quote is approved).
- [ ] Every run is logged on the business's automation page and on the affected record: what
      triggered it, what ran, what was skipped and why.
- [ ] Safeguards: a client never receives the same automated message more than once per
      document. Rules can't trigger each other in loops. Automations pause for suspended
      businesses and respect bounce suppression.
- [ ] Automations are a plan feature (BIL-01) with a limit on active rules per plan.
- [ ] Tests cover delays, condition re-checks, idempotency, loop prevention, logs and tenancy.

## Out of scope

- A visual flow builder, arbitrary branching, outbound webhooks or Zapier (backlog), and SMS
  actions until SMS exists.

## Open questions

- Should the "auto-create job on approval" setting from JOB-01 become a recipe instead?
  Recommend yes, to keep one mechanism.
- How many recipes ship at launch? Recommend the four listed.
