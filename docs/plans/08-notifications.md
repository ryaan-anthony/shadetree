# 08 · Notifications & automations

## Purpose

Deliver the right message to the right person reliably, and automate the follow-ups owners forget: clients get branded, trustworthy emails
about their quotes, visits and invoices; team members learn about things that need them. Other
domains decide *when* to notify; this domain owns *how* messages are delivered.

## Current state

Devise mailers only. Unused tables for message templates, notification triggers (a rules
engine with conditions, channels and timing offsets), and client notification preferences.

## Requirements

### Email delivery foundation
- **R1** Client-facing emails are sent from a Shadetree sending domain with proper
  authentication (SPF, DKIM, DMARC), display the business's name as sender and use the
  business's email as reply-to.
- **R2** A shared branded email layout uses the business's logo and color, with a plain-text
  alternative, and renders well in major clients and on phones.
- **R3** Every outbound message is recorded per business: recipient, type, related document,
  sent time, and delivery outcome (delivered, bounced, complained) when the provider reports it.
- **R4** Hard bounces and complaints suppress future sends to that address for that business and
  surface a warning on the client record.
- **R5** Sending is asynchronous and retried on transient failure; a failed send is visible to
  the business on the related document.
- **R6** Emails never contain secrets beyond the client link; links expire per PLT-12.

### Team notifications
- **R7** Team members receive in-app notifications (with an unread count) and optionally email,
  for: new request, quote viewed (first time), quote approved/declined/changes requested, visit
  assigned to me / changed, invoice paid, payment failed.
- **R8** Each member chooses email on/off per notification type; in-app is always on.
- **R9** Notifications link straight to the relevant record and are role-aware (technicians only
  get notifications for their visits).

### Message catalog
- **R10** The full list of messages (client-facing and team) with trigger, recipient, and
  default copy is documented in one place, so domains don't invent ad-hoc emails.

| Message | Recipient | Trigger (owning spec) |
| --- | --- | --- |
| Request received | Client | CLI-03 |
| New request | Team | CLI-03 |
| Quote sent | Client | QTE-04 |
| Quote viewed / approved / declined / changes requested | Team | QTE-05 |
| Visit scheduled / changed / cancelled / reminder | Client | JOB-05 |
| Visit assigned / changed | Technician | JOB-02 |
| Invoice sent | Client | PAY-02 |
| Payment receipt | Client | PAY-04 |
| Invoice paid | Team | PAY-04, PAY-05 |
| Team invitation | Invitee | ACC-03 |

### Message templates (paid plans)
- **R11** Businesses can edit the wording of client-facing messages, using placeholders and a
  live preview, and can create extra templates for automations. The layout, links and legal
  footer stay fixed.

### Workflow automations (paid plans)
- **R12** A business can create rules: a trigger from a catalog of core-flow events, an
  optional delay, optional conditions, and actions from a fixed catalog (send a template,
  notify the team, create a job, create and send an invoice, tag a client).
- **R13** Ready-made recipes cover the common cases (quote follow-up, overdue invoice reminder,
  auto-invoice on completion, review request) and switch on in one step.
- **R14** Conditions are re-checked before acting. Every run is logged with what ran and what
  was skipped.
- **R15** Safeguards: no duplicate client messages per document, no rule loops, respect for
  suspensions and bounce suppression, and limits on active rules per plan.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Fixed message types with defaults at launch. Automations come in M5 as rules built from fixed trigger, condition and action catalogs, plus recipes, rather than a free-form engine. | Automations drive follow-up revenue, but catalogs keep them supportable and testable. |
| D2 | Email only at launch; SMS is a paid, metered backlog feature. | SMS has real per-message cost and 10DLC/TCPA compliance overhead. |
| D3 | No broadcast/marketing messages. | Legal risk (CAN-SPAM/TCPA) and deliverability risk for the shared sending domain. |
| D4 | Business-editable copy arrives in M5 (NTF-03), before automations. | Defaults plus a personal message per send cover the MVP. Automations need editable templates. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [NTF-01](../specs/notifications/NTF-01-email-foundation.md) | Transactional email foundation | M2 | CAT-02 |
| [NTF-02](../specs/notifications/NTF-02-team-notifications.md) | Team notifications | M3 | NTF-01, ACC-04 |
| [NTF-03](../specs/notifications/NTF-03-message-templates.md) | Editable message templates | M5 | NTF-01, BIL-01 |
| [NTF-04](../specs/notifications/NTF-04-workflow-automations.md) | Workflow automations | M5 | NTF-02, NTF-03, QTE-06, JOB-02, PAY-02 |

## Backlog (M6)

- SMS for quotes, visit reminders, invoices (opt-in, STOP handling, metered per plan).
- Sending from a business's own domain (domain authentication per business).
- Web push / PWA notifications for technicians.
- Client-level communication preferences (beyond unsubscribe from optional messages).

## Open questions

1. ~~Email provider choice~~: decided, the provider's SMTP relay in production, with no
   provider integration ([ADR 0017](../adr/0017-transactional-email-smtp.md)). In development,
   letter_opener_web opens every email in the browser.
2. ~~Sending domain~~: decided, the root domain `getshadetree.com` (G8).
3. Should reminder emails (visit reminders) be considered "transactional"? Recommend yes, with
   an opt-out link anyway.
