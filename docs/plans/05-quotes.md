# 05 · Quotes

## Purpose

The heart of the product. A business builds a professional, branded quote in under three
minutes and the client approves it from their phone in one tap. This is the first moment of
real value and the metric we price on.

## Current state

Nothing implemented. The original plan described quote display and approval only from the
client's side and treated signatures as a separate legal-compliance epic.

## Requirements

### Building
- **R1** Create a quote for a client and (optionally) a property, from scratch or from a request.
- **R2** Add line items from the catalog (copying name, description, unit, price, taxability) or
  as free-form items. Edit quantity, unit price, description; reorder; remove.
- **R3** Discounts per line or on the whole quote (fixed or percent). Taxes per the business's
  rates. Totals are always exact and shown live as items change.
- **R4** Quote-level fields: title, message to client, internal notes (never shown to client),
  terms/conditions (defaulted from business settings), expiry date (defaulted, e.g. 30 days),
  optional attachments/photos.
- **R5** Quotes are numbered sequentially per business with a configurable prefix.
- **R6** Drafts autosave or save explicitly without losing work on a phone.

### Sending
- **R7** Send by email with a personal message; the email contains a button to the client link
  and the PDF attached. Copy-link is available for sending via the business's own SMS/WhatsApp.
- **R8** Sending requires a confirmed account and a client email (or copy-link). Sending counts
  toward plan usage (09-billing).
- **R9** Record when the quote is sent, first viewed, and each later view.

### Client experience
- **R10** The client link opens a fast, branded, mobile-first page showing business identity,
  line items, totals, message, terms, attachments, expiry and a PDF download.
- **R11** The client can **Approve** (types their name to sign and confirms terms), **Decline**
  (optional reason), or **Request changes** (free-text message).
- **R12** Approval records: signer name, timestamp, IP/user-agent, and an immutable snapshot of
  exactly what was approved (version). The approved quote can't be edited.
- **R13** After approval, the client sees next steps (e.g. "We'll contact you to schedule").
  Later: deposit payment and self-scheduling (backlog).
- **R14** Expired quotes can be viewed but not approved; the client can ask for a refresh.

### Lifecycle
- **R15** Statuses: Draft → Sent → (Viewed) → Approved | Declined | Changes requested | Expired.
  Approved quotes can be converted to a job (06-jobs) and/or invoice (07-payments).
- **R16** Editing a sent quote creates a new revision; the client link always shows the latest,
  and earlier revisions remain viewable to staff.
- **R17** The business is notified (email + in-app) on view (first only), approve, decline and
  change request.
- **R20** Members whose role allows it can draft, and optionally send, quotes for requests
  assigned to them, without wider office access (04-clients R20).
- **R21** A business can mark services that technicians may send quotes for without office
  review; a draft made only of those services, at their prices, can be sent by its technician.
- **R18** Quote list with status filters, search by client/number, and totals; staff can
  duplicate, archive, mark approved on the client's behalf (records who and why) and resend.

### PDF
- **R19** Every quote renders as a branded PDF that matches the web view and is suitable for
  printing and attaching.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Typed-name signature + consent checkbox + audit snapshot is the approval standard. | Adequate evidence for service quotes; far simpler than a signature-compliance framework. Drawn signature is backlog. |
| D2 | Revisions replace the "change request system" as a separate object. | Simpler mental model: client asks, business revises and resends. |
| D3 | "Quote sent" is the usage metric (pending G3). | Directly tied to value and easy for owners to understand. |
| D4 | Optional/alternative line items (good-better-best) are backlog. | High value but adds complexity to approval and totals; do after MVP. |
| D5 | SMS sending of quotes waits for 08-notifications SMS work. | Copy-link covers SMS at zero cost to us. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [QTE-01](../specs/quotes/QTE-01-quote-builder.md) | Quote builder | M2 | CLI-01, CAT-03, CAT-04, PLT-08 |
| [QTE-02](../specs/quotes/QTE-02-quote-pdf.md) | Quote PDF | M2 | QTE-01, CAT-02 |
| [QTE-03](../specs/quotes/QTE-03-client-quote-page.md) | Client quote page | M2 | QTE-01, PLT-12, CAT-02 |
| [QTE-04](../specs/quotes/QTE-04-send-quote.md) | Send quote | M2 | QTE-02, QTE-03, NTF-01 |
| [QTE-05](../specs/quotes/QTE-05-client-approval.md) | Client approve / decline / request changes | M2 | QTE-03, NTF-01 |
| [QTE-06](../specs/quotes/QTE-06-quote-lifecycle.md) | Quote list, lifecycle & revisions | M2 | QTE-04, QTE-05 |
| [QTE-07](../specs/quotes/QTE-07-technician-quotes.md) | Quotes from assigned requests | M6 | JOB-06, QTE-01, ACC-07 |
| [QTE-08](../specs/quotes/QTE-08-auto-approved-services.md) | Services technicians send without review | M6 | QTE-07, CAT-03, BIL-03 |

## Backlog (M6)

- Optional line items / packages the client chooses between.
- Quote templates (saved sets of line items and text).
- Automatic follow-up reminders for unviewed / unapproved quotes.
- Require a deposit on approval (with 07-payments).
- Approve-and-schedule in one step (with 06-jobs self-scheduling).
- Drawn signature capture.
- Technicians creating quotes in the field.
- AI-assisted line items from a request description and photos.

## Open questions

1. Can a business edit the terms per quote, or only globally? Recommend default from settings,
   editable per quote.
2. On revision after approval: allowed (creates new revision requiring re-approval) or blocked?
   Recommend blocked; duplicate instead.
3. Do we show "viewed" receipts to the business? (Some clients find it intrusive.) Recommend yes.
4. Should declined/expired quotes count toward usage? Recommend yes — the send is the usage.
