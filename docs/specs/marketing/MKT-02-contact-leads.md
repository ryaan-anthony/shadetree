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

- [ ] The contact form collects name, email, optional business name and industry, and message;
      validation errors are clear and inline.
- [ ] Submissions are stored and visible to operators (a simple list in the operator console, or
      a temporary admin view until OPS-01 lands).
- [ ] The team receives an email per submission with reply-to set to the sender.
- [ ] The sender sees a confirmation page and receives a confirmation email.
- [ ] Invisible spam protection and rate limiting per PLT-13; obvious spam is discarded or
      flagged without notifying the team.
- [ ] Submitted personal data is covered by the privacy policy and deletable on request.
- [ ] Tests cover success, validation, spam rejection and notification.

## Out of scope

- Newsletter signup, CRM integration, live chat, demo booking (not planned at launch).

## Open questions

- Where should team notifications go — the founder's inbox or a shared support address?
  Recommend a support@ address on the product domain (depends on G8).
