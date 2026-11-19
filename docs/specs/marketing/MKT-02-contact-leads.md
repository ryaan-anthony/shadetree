---
id: MKT-02
title: Contact form & leads
domain: marketing
milestone: M5
depends_on: [NTF-01, PLT-13]
---
# MKT-02 · Contact form & leads

> Requirements: [11-marketing](../../plans/11-marketing.md) R5

## Summary

The contact form currently posts without saving or notifying anyone. Make it work end to end:
messages are stored, the team is notified, the sender gets a confirmation, and spam is kept out.

## User stories

- As a prospect, I want to ask a question and know it was received.
- As the founder, I want every message in one place and in my inbox so that none are missed.

## Acceptance criteria

- [x] The contact form collects name, email, optional business name and industry, and message;
      validation errors are clear and inline.
- [ ] Submissions are stored and visible to operators (a simple list in the operator console, or
      a temporary admin view until OPS-01 lands).
- [x] The team receives an email per submission with reply-to set to the sender.
- [x] The sender sees a confirmation page and receives a confirmation email.
- [x] Invisible spam protection and rate limiting per PLT-13; obvious spam is discarded or
      flagged without notifying the team.
- [x] Submitted personal data is covered by the privacy policy and deletable on request.
- [x] Tests cover success, validation, spam rejection and notification.

## Out of scope

- Newsletter signup, CRM integration, live chat, demo booking (not planned at launch).

## Decisions

- **Team notifications go to support@getshadetree.com** (recommendation accepted, M5 planning),
  set by `SUPPORT_EMAIL`.
- **Spam is flagged, not dropped**: a message with a link in the name, more than two links, or
  obvious spam words is kept with its reason for operators to check, and nobody is emailed.
  Bots that fill the hidden field are dropped outright and shown the usual page.

## Implementation notes

Part 1 (the form, storage and email):
- `ContactMessage` (platform-level, no business): name, email, optional business name and
  industry (the setup list plus Other), message, and the sender's IP and browser for abuse
  checks. Names and business names lose control characters, so they can't reach mail headers.
- The team's email has reply-to set to the sender. The sender's confirmation doesn't repeat what
  they wrote, and goes at most once an hour per address, so the form can't flood someone's
  inbox or relay a message to them. The "Message sent" page only mentions it when one was sent.
- Guards (PLT-13): hidden field, single-use form token with a minimum fill time, five messages
  per network per ten minutes. Errors are inline, in plain words.
- Kept two years, spam 30 days (`PruneContactMessagesJob`, daily). `bin/rails contact:erase
  EMAIL=…` removes a person's messages on request; the Privacy Policy (MKT-03) lists messages
  and their retention.

Part 2 (after OPS-01 merges): the operator console lists messages (spam filter, mark handled,
delete) — the remaining criterion.

## Open questions

- None open. The support@ mailbox must exist before launch.
