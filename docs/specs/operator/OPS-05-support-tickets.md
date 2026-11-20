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
- [x] Members see their business's tickets (as their role allows) with status (Open, Waiting on
      you, Resolved) and threaded replies.
- [x] Operators get a ticket inbox in the console: filter by status, category, plan and
      assignee; assign to an operator; reply; add internal notes; change status. Each ticket
      links to the business page (OPS-02).
- [x] Replies reach the member by email and in the app (NTF-02). Replying to the email adds to
      the thread. Emails to the support address from a known member's email open or continue a
      ticket. *(Built and tested in the app. Met only once the Cloudflare Worker and routing in
      ops-work are applied and `INBOUND_EMAIL_ENABLED` is set (docs/runbooks/inbound-email.md);
      until then members reply in the app.)*
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
- Any member, technicians included, can open a ticket. People without office access see only
  the tickets they opened, and billing tickets need the billing permission; everyone sees their
  own (owner's decision; `SupportTicket.visible_to`). "Waiting on you" tickets auto-resolve
  after 7 days (`SUPPORT_AUTO_RESOLVE_DAYS`).
- Email reaches the app through Cloudflare Email Routing and an Email Worker (owner, 2026-11-20;
  [ADR 0021](../../adr/0021-inbound-support-email.md)). Replies thread only through a signed
  per-member reply address, from that member, with Cloudflare's SPF/DKIM/DMARC pass; new
  tickets need DMARC pass and an active member. Subject lines and Message-IDs are never trusted.

## Implementation notes

- `SupportTicket`/`SupportMessage` (business-owned; messages can be internal notes). Members:
  Help menu in the top bar, `/admin/help`; the page (an `/admin` path) and browser are attached;
  screenshots are re-encoded without metadata. A member's reply reopens the ticket.
- Operators: `/ops/tickets` (filters; open count in the nav), the business beside each ticket;
  assign, reply with the next status, note, set status; all audited as `ticket.*`.
- Replies: NTF-02 `support_reply` to the opener; `SupportMailer#reply` with `[#uid]` in the
  subject; reply-to is the member's `support+<token>@` address once `INBOUND_EMAIL_ENABLED` is on
  (copy: "Reply to this email or in Shadetree"), else the support address ("Reply in Shadetree").
- Inbound: the Worker's signed post to `/inbound/support_email` (HMAC, 5 minutes, 25 MiB) is
  stored by Action Mailbox (incinerated after 14 days), and `SupportMailbox` → `SupportMail`
  replies, opens or drops it quietly (bounces and auto-replies too), logging only the outcome.
  Email shares the app form's hourly counters per person and business. A Cc'd support@ copy of
  a reply is dropped; a reply that fails the sender checks leaves an operator-only note.
- Limits: 10 messages an hour per person, 30 per business; screenshots need a confirmed account
  and open through a checked, 5-minute link. Replies reach every active member who wrote on the
  ticket (else the Owners). Operators opening a ticket is audited (`ticket.viewed`).
- `ResolveStaleSupportTicketsJob` (daily) re-checks each ticket under a lock, so a reply in the
  meantime wins, and resolves it with a notice in the thread, app and email.
- Data: tickets and screenshots are kept while the business exists and go with it; they aren't in
  INS-02 exports and client erasure doesn't scan them (members are asked to leave client details out).
- Dev seeds: a ticket with a reply, a note and an answer by email. Tests: `test/integration/admin/support_tickets_test.rb`,
  `test/integration/ops/support_inbox_test.rb`, `test/models/support_{mail,ticket}_test.rb`,
  `test/integration/inbound/support_emails_test.rb`.

## Open questions

- None. The email path (above) was settled on 2026-11-20.
