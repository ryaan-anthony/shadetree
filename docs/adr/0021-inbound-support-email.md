# 0021. Inbound support email through Cloudflare Email Routing and a signed Worker post

- **Status:** Accepted
- **Date:** 2026-11-20
- **Specs:** OPS-05

## Context

[ADR 0020](0020-in-app-support-tickets.md) left open how email to the support address reaches
the app, and so how a sender is proven genuine: the From header can be forged by anyone.
Outgoing email (ADR 0017) is plain SMTP, so whichever path is chosen for incoming mail is new.
The domain's DNS is on Cloudflare, managed with Terraform in the separate ops-work repository.

## Options considered

1. **The email provider's inbound routing posting to the app**: ties incoming mail to the
   sending provider, usually a paid tier.
2. **A mailbox the app polls (IMAP)**: a stored password, polling, and authentication results
   that depend on the mailbox host.
3. **Cloudflare Email Routing with an Email Worker** (free tier): Cloudflare checks SPF, DKIM
   and DMARC before the Worker runs and records them in its own, first `Authentication-Results`
   header. The Worker forwards a copy to the human support inbox and posts the raw message to
   the app, signed with a shared secret.

## Decision

Option 3 (product owner, 2026-11-20). The Worker posts to `POST /inbound/support_email`, signed
with HMAC-SHA256 over the timestamp, a base64url JSON envelope (envelope sender and recipient)
and the raw body; the app refuses anything more than 5 minutes off, wrongly signed or over
25 MiB (contract: `docs/runbooks/inbound-email.md`). Cloudflare's verdict is read from the
signed raw message: its first `Authentication-Results` field, which Cloudflare prepends (the
Worker's `Headers.get` joins repeated headers, so a sender's could be mistaken for it). The
app stores the message with **Action Mailbox** (its own ingress; the built-in ones stay off)
and incinerates it after 14 days. `SupportMail` then trusts a message only when:

- it's a reply: sent to the member's signed reply address `support+<token>@getshadetree.com`
  (ticket and user, MAC'd with a key derived from the app's secret), from that user's address,
  with Cloudflare reporting DMARC pass or an SPF/DKIM pass aligned with the From domain;
- it's new: DMARC pass, from an active member. Subject lines and Message-IDs are never authority.

Anything else, and any automatic mail (bounces, auto-replies, lists), is dropped quietly, with
no reply, and logged without addresses. Each sender and business is rate limited as in the app.

## Consequences

- Members answer support by email and it lands in the ticket; the human inbox still gets a copy
  of everything, so an app outage loses nothing.
- Cloudflare becomes a processor of incoming support email (sub-processors page).
- The Worker and the Email Routing rules live in ops-work (Terraform); subaddressing (`+`) must
  be on for the zone. Rotating `INBOUND_EMAIL_SECRET` means updating the Worker secret and the
  app together.
- Reply addresses don't expire; leaving the business, or losing sight of the ticket, ends them.
- **Cost:** none (Email Routing and Workers free tiers).
