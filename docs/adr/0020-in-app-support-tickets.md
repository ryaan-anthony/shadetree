# 0020. Support tickets built into the app

- **Status:** Accepted
- **Date:** 2026-11-19
- **Specs:** OPS-05

## Context

Businesses need one obvious place to ask Shadetree for help, and operators need one queue to
answer from, with the business's plan and activity beside each request (10-operator R14–R16).
OPS-05 asked whether to build this or integrate an external helpdesk. The product owner decided:
tickets are only between a business and Shadetree (never a helpdesk for a business's own clients),
and they're built in the app, like the rest of the console ([ADR 0019](0019-hand-built-operator-console.md)).

## Options considered

1. **An external helpdesk** with a widget and API: mature inbox, email handling and macros.
   Cons: a monthly per-seat cost, a second place operators work, member and business context
   copied out of the app through an API, another processor of members' data, and its own
   sign-in and audit trail outside OPS-01's log.
2. **In the app**: a ticket and its messages are business-owned records; members use them from
   a Help menu, operators from the console. Pros: the business's context is a join away,
   tenancy, roles and the audit log apply as they do everywhere, no new service or cost. Cons:
   each feature (inbox filters, email threading) is written by hand.

## Decision

Build tickets in the app: `SupportTicket` and `SupportMessage` (business-owned), the member side
under `/admin/help`, the inbox under `/ops/tickets`. Replies reach members through NTF-02 (in the
app, and by email from "Shadetree Support" with the support address as reply-to). Each email
carries the ticket's reference in its subject and Message-ID, and `SupportMail.receive` threads
an incoming email into the right ticket, or opens one for a known member.

## Consequences

- One stack, one audit log, no extra cost; the console stays small and purpose-built.
- How email to the support address reaches the app, and how a sender is proven genuine, is
  [ADR 0021](0021-inbound-support-email.md) (Cloudflare Email Routing and a signed Worker post).
- Live chat, a knowledge base and response-time reporting would be new work (backlog).
- **Cost:** none.
