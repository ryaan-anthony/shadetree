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

- [ ] Any member can open a ticket from a Help menu: subject, category (question, bug, billing,
      feature request), message and attachments (screenshots). The page they were on and their
      browser details are attached automatically.
- [ ] Members see their business's tickets with status (Open, Waiting on you, Resolved) and
      threaded replies.
- [ ] Operators get a ticket inbox in the console: filter by status, category, plan and
      assignee; assign to an operator; reply; add internal notes; change status. Each ticket
      links to the business page (OPS-02).
- [ ] Replies reach the member by email and in the app (NTF-02). Replying to the email adds to
      the thread. Emails to the support address from a known member's email open or continue a
      ticket.
- [ ] Resolved tickets reopen when the member replies. Stale "Waiting on you" tickets
      auto-resolve after a set period, with notice.
- [ ] Tickets never expose client personal data to operators beyond what the member included.
- [ ] Ticket actions are recorded in the operator audit log (OPS-01).
- [ ] Tests cover ticket creation, email reply threading, permissions and tenancy.

## Out of scope

- Live chat, a knowledge base, SLAs and response-time reporting (backlog). Helpdesk for a
  business's own clients (see open questions).

## Open questions

- **(blocking for scoping)** Does "support ticketing" also mean a helpdesk for each business's
  *own clients* (client questions about quotes and invoices, tracked as tickets)? If yes, it
  needs a separate spec in 04-clients. The recommended interim answer is that client replies
  thread into the request/quote timeline.
- Build in-app or integrate an external helpdesk tool? Engineering/cost decision; record in an ADR.
