# Inbound support email

> OPS-05, [ADR 0021](../adr/0021-inbound-support-email.md). How email to the support address
> reaches support tickets, the contract between the Cloudflare Email Worker and the app, and
> how to turn it on, rotate the secret and check it. (When the operations runbook from PLT-09
> lands, link this page from it.)

## How mail flows

1. Mail to `support@getshadetree.com` (or a member's reply address
   `support+<token>@getshadetree.com`) reaches **Cloudflare Email Routing**, which checks SPF,
   DKIM and DMARC and adds its own `Authentication-Results: mx.cloudflare.net; …` header at the
   top. Since July 2025 it only passes on mail that passes SPF or DKIM.
2. The routing rule for the environment's support address runs that environment's
   **shadetree-support-email Worker** (`infra/support-email-worker`, deployed once per
   environment with the routing rules by Terraform `infra/email.tf`, [ADR 0027](../adr/0026-cloud-config-in-this-repository.md)).
   Production is `support@getshadetree.com`; staging is `support-staging@getshadetree.com` (the
   apex, since `staging.getshadetree.com` is the tunnel's CNAME). Each Worker posts to its own
   environment with its own secret. It:
   - rejects anything over 25 MiB;
   - always forwards a copy to the human support inbox (a verified Email Routing destination,
     from the Worker's `HUMAN_INBOX` setting);
   - posts the raw message to the app, signed (below). If the app is down or refuses it, the
     Worker logs it and doesn't reject the mail: the human copy exists. The reverse also holds:
     if forwarding fails (an unverified inbox, say) but the post succeeds, the message exists
     **only in the app** (the Worker logs `support_email.forward_failed`); if both fail the
     Worker throws, so Cloudflare reports a failure instead of accepting it.
3. The app (`Inbound::SupportEmailsController`) checks the signature, stores the message with
   Action Mailbox and routes it to `SupportMailbox`, which hands it to `SupportMail` with the
   envelope recipient and Cloudflare's result. Raw messages are incinerated 14 days after
   processing; `PurgeInboundEmailsJob` (daily) removes any older one left behind.
4. `SupportMail` adds a reply to its ticket, opens a ticket for a member, or drops the message
   quietly (logged as `support_mail.received` with an `outcome`, never an address).

`privacy@`, `legal@` and `security@` are forwarded straight to the human inbox; they never reach
the app.

## The signed post (contract, version 1)

`POST https://<app host>/inbound/support_email`

| Header | Value |
| --- | --- |
| `Content-Type` | `message/rfc822` |
| `X-Shadetree-Timestamp` | Unix time in seconds when the Worker signed it |
| `X-Shadetree-Envelope` | base64url (no padding) of the JSON `{"from": envelope sender, "to": envelope recipient}` |
| `X-Shadetree-Signature` | `v1=` + lowercase hex HMAC-SHA256 |

- What Cloudflare found (SPF, DKIM, DMARC) isn't sent separately: the app reads it from the
  signed raw message, taking the **first** `Authentication-Results` field (Cloudflare prepends
  its own) and only if its authserv-id is `mx.cloudflare.net`. Any later one may have been
  written by the sender and is ignored. (The Worker can't do this reliably: `Headers.get` joins
  repeated headers with ", ".) Confirm on the first live message that Cloudflare's header is
  indeed first in the raw source.
- The body is the raw message, byte for byte (`message.raw`).
- Signature input: the bytes of `<timestamp>` + `.` + `<X-Shadetree-Envelope value>` + `.` +
  `<raw body>`, keyed with `INBOUND_EMAIL_SECRET` (UTF-8 bytes of the secret).

The app answers:

| Status | Meaning | Worker should |
| --- | --- | --- |
| 204 | Stored (or already stored: a retry of the same bytes to the same recipient is a no-op) | Done |
| 401 | Bad or missing signature, or timestamp more than 5 minutes off | Log; check the secret and clock |
| 404 | The app has no `INBOUND_EMAIL_SECRET` | Log |
| 413 | Over 25 MiB | Log |
| 422 | The envelope recipient isn't the support address | Log |
| 429 | More than 30 failed posts (bad signature, too large) a minute from one IP address; signed posts are never limited, since Cloudflare's egress addresses are shared | Log |

## App settings

| Setting | What |
| --- | --- |
| `INBOUND_EMAIL_SECRET` | Shared with the Worker; at least 32 characters (`openssl rand -hex 32`). Without it the endpoint is "not found". Credentials key `inbound_email_secret` also works. |
| `INBOUND_EMAIL_ENABLED` | `true` once Email Routing and the Worker are live: support emails then say "Reply to this email or in Shadetree" and carry the member's signed reply address as Reply-To. Otherwise they say "Reply in Shadetree" and reply to `support@`. |
| `SUPPORT_EMAIL` | The support address (default `support@getshadetree.com`). Staging: `support-staging@getshadetree.com`, so its reply addresses (`support-staging+<token>@`) reach the staging Worker. |

## Turning it on

1. Generate the secret; set it as the app's `INBOUND_EMAIL_SECRET` and deploy.
2. In `infra/` ([README](../../infra/README.md), "Support email"): enable Email Routing, keep **one** merged
   SPF record (the outgoing provider's plus `include:_spf.mx.cloudflare.net`), turn on
   subaddressing (a manual step; without it every emailed reply bounces once step 4 is done),
   apply `infra/` with the same secret, and verify the human inbox.
3. Send a test email to `support@` from a member's address: the human inbox gets a copy, and a
   ticket opens in the app. Check the Worker's logs and the app's `inbound_email.*` lines.
4. Set `INBOUND_EMAIL_ENABLED=true` and deploy; reply to a ticket and answer the email.
   Answers to support emails sent **before** this step (Reply-To `support@`, no signed address)
   open new tickets rather than threading: subjects are never used to match.

## Rotating the secret

Set the new secret on the Worker and the app within a few minutes of each other. Mail that
arrives in between is refused by the app (401) but still reaches the human inbox.

Reply addresses are signed with a key derived from `secret_key_base`: rotating that invalidates
**every** reply address already sent. Answers to old emails are then dropped (`bad_token`) and
only reach the human inbox.

## When something looks wrong

- Nothing reaches the app: the Worker's logs show the app's status (table above).
- A member's reply didn't thread: look up `support_mail.received` for the time; the `outcome`
  says why (`bad_token`, `forged_sender`, `unauthenticated`, `not_member`, `rate_limited`, `duplicate`,
  `automated`, …). The human inbox has the message.
- Request bodies are capped at 26 MiB by Puma (`http_content_length_limit`, PLT-09) and at
  25 MiB by the app itself; nothing else in front of it needs a limit.
