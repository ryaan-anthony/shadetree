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

- [ ] Owners/Admins can edit the subject and body text of every client-facing message in the
      message catalog. The branded layout, buttons and legal footer can't be edited.
- [ ] Placeholders are offered from a documented list per message (client first name, business
      name, document number, total, due date, visit window, link). Unknown placeholders are
      flagged before saving.
- [ ] A live preview renders the message with sample data, or with a real recent record when
      one is chosen.
- [ ] Templates can be reset to the default. Edited templates are marked as customized.
- [ ] Owners/Admins can also create additional custom templates (subject and body with
      placeholders) for use by automations and manual sends.
- [ ] Text is sanitized: a template can't inject markup or scripts and can't remove the client
      link.
- [ ] Editing templates is a plan feature (BIL-01). On downgrade, customized templates keep
      sending but are read-only.
- [ ] Tests cover rendering, placeholder validation, sanitization, reset and tenancy.

## Out of scope

- Visual email designer, attachments in custom templates, multiple languages (backlog).

## Open questions

- Should team (internal) notification wording also be editable? Recommend no.
