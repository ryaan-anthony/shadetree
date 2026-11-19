---
id: NTF-03
title: Editable message templates
domain: notifications
milestone: M5
depends_on: [NTF-01, BIL-01]
---
# NTF-03 · Editable message templates

> Requirements: [08-notifications](../../plans/08-notifications.md) R11

## Summary

Default emails are fine for launch, but businesses want to sound like themselves. Let them edit
the wording of each client-facing message, using placeholders for client and document details,
with a live preview. Automations (NTF-04) send these same templates.

## User stories

- As an owner, I want my quote email to sound like me, not like software.
- As an owner, I want to preview exactly what a client will receive before I save.
- As an owner, I want to go back to the default wording if I make a mess of it.

## Acceptance criteria

- [x] Owners/Admins can edit the subject and body text of every client-facing message in the
      message catalog. The branded layout, buttons and legal footer can't be edited.
- [x] Placeholders are offered from a documented list per message (client first name, business
      name, document number, total, due date, visit window, link). Unknown placeholders are
      flagged before saving.
- [ ] A live preview renders the message with sample data, or with a real recent record when
      one is chosen.
- [x] Templates can be reset to the default. Edited templates are marked as customized.
- [ ] Owners/Admins can also create additional custom templates (subject and body with
      placeholders) for use by automations and manual sends.
- [x] Text is sanitized: a template can't inject markup or scripts and can't remove the client
      link.
- [x] Editing templates is a plan feature (BIL-01). On downgrade, customized templates keep
      sending but are read-only.
- [x] Tests cover rendering, placeholder validation, sanitization, reset and tenancy.

## Out of scope

- Visual email designer, attachments in custom templates, multiple languages (backlog).

## Decisions

- **Team notifications aren't editable** (recommendation accepted, M5 planning): only the client
  emails in the catalog.
- **Only the subject and opening text are editable.** The summary, the button to the client's
  page, attachments and footer are fixed, so the link can't be removed and the details always
  match the document. For quote and invoice emails, the template is the note the send form
  starts with (still editable per send), since those already carry a personal message.

## Implementation notes

Part 1 (editing the catalog's client emails):
- `MessageTemplate` (one per business and kind) holds a subject and plain-text body; without
  one, the product's own wording is used, unchanged. `DEFINITIONS` lists each editable email
  with its default (the same words the product sends) and its placeholders; `{{name}}` is
  filled in by `MessageTemplate::Values` when the email is built. Unknown placeholders and any
  HTML are refused when saving; everything is escaped when sent, and a blank line makes a
  paragraph.
- Settings → Messages (`business_settings`): the list marks customized emails; the editor has
  placeholder buttons that insert at the cursor and a live preview (server-rendered as you
  type, with sample details and the business's own name), and "Go back to the default wording".
- Mailers ask `custom_subject(kind, values)`: request received, quote approved, visit booked /
  moved / cancelled / reminder (mixed changes use "moved"), payment receipt. Quote and invoice
  send forms start from the template's subject and note.
- Plan feature `message_templates`: without it the pages are read-only (with a link to plans),
  and saved templates keep sending.

Part 2: extra templates of a business's own (for automations and manual sends), choosing one
in the send forms, and previewing with a real recent record.

## Open questions

- None.
