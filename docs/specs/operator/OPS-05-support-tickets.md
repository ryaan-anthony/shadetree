---
id: OPS-05
title: Support tickets
domain: operator
milestone: M5
depends_on: [OPS-02, NTF-02]
---
# OPS-05 · Support tickets

> Requirements: [10-operator](../../plans/10-operator.md) R14–R16

## Summary

Give businesses one obvious place to ask Shadetree for help and give operators one inbox to
answer from. Tickets carry the business's context automatically, conversations continue by
email, and nothing gets lost in a personal inbox.

## User stories

- As an owner who's stuck, I want to ask for help without leaving the app.
- As an operator, I want every request in one queue, with the business's plan and recent
  activity beside it.
- As an owner, I want to reply from my email and still have the conversation in the app.

## Acceptance criteria

- [x] Any member can open a ticket from a Help menu: subject, category (question, bug, billing,
      feature request), message and attachments (screenshots). The page they were on and their
      browser details are attached automatically.
- [x] Members see their business's tickets with status (Open, Waiting on you, Resolved) and
      threaded replies.
- [x] Operators get a ticket inbox in the console: filter by status, category, plan and
      assignee; assign to an operator; reply; add internal notes; change status. Each ticket
      links to the business page (OPS-02).
- [ ] Replies reach the member by email and in the app (NTF-02). Replying to the email adds to
      the thread. Emails to the support address from a known member's email open or continue a
      ticket. *(Replies by email and in the app are done, and threading is built and tested
      (`SupportMail.receive`); getting email into the app waits on the open question below.)*
- [x] Resolved tickets reopen when the member replies. Stale "Waiting on you" tickets
      auto-resolve after a set period, with notice.
- [x] Tickets never expose client personal data to operators beyond what the member included.
- [x] Ticket actions are recorded in the operator audit log (OPS-01).
- [x] Tests cover ticket creation, email reply threading, permissions and tenancy.

## Out of scope

- Live chat, a knowledge base, SLAs and response-time reporting (backlog). Helpdesk for a
  business's own clients.

## Decisions

- Tickets are only between a business and Shadetree, never a helpdesk for a business's own
  clients (product owner).
- Built in the app, like the console ([ADR 0020](../../adr/0020-in-app-support-tickets.md)).
- Any member, technicians included, opens and sees the business's tickets. "Waiting on you"
  tickets auto-resolve after 7 days (`SUPPORT_AUTO_RESOLVE_DAYS`).

## Implementation notes

- `SupportTicket`/`SupportMessage` (business-owned; messages can be internal notes). Members:
  Help menu in the top bar, `/admin/help`; the page (an `/admin` path) and browser are attached;
  screenshots are re-encoded without metadata. A member's reply reopens the ticket.
- Operators: `/ops/tickets` (filters; open count in the nav), the business beside each ticket;
  assign, reply with the next status, note, set status; all audited as `ticket.*`.
- Replies: NTF-02 `support_reply` to the opener; `SupportMailer#reply` with reply-to the
  support address, `[#uid]` in the subject and a `ticket-<uid>-…` Message-ID.
- `ResolveStaleSupportTicketsJob` (daily) resolves with a notice in the thread, app and email.
- Dev seeds: a ticket with a reply and a note. Tests: `test/integration/admin/support_tickets_test.rb`,
  `test/integration/ops/support_inbox_test.rb`, `test/models/support_{mail,ticket}_test.rb`.

## Open questions

- **(blocking for email threading)** How does email to the support address reach the app: the
  provider's inbound routing posting each message to the app, or a mailbox the app reads? It
  also decides how a sender is proven genuine (`SupportMail.receive` trusts the From address).
