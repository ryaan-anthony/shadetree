# 0028. Late bounces arrive at one generic, signed bounce-event endpoint

- **Status:** Accepted
- **Date:** 2026-11-22
- **Specs:** NTF-05, NTF-01, QTE-04, PAY-02
- **Supersedes in part:** [0017](0017-transactional-email-smtp.md) ("bounces and complaints after
  acceptance stay in the provider's dashboard")

## Context

Client email goes out over plain SMTP with no provider integration (ADR 0017). The app learns
only what the SMTP conversation says. Most relays accept any well-formed recipient and bounce
later, so a quote or invoice can show as sent while the client never got it. QTE-04's
"Email not delivered" warning, the team notification and Resend (QA #274, #277) only fire for
refusals at send time.

The owner wants late bounces captured without tying the code to a provider: SMTP stays, the
provider can change by configuration, and no provider is named in the codebase. The app already
has a signed ingress for support email (ADR 0021) and a store-once event pattern (`ConnectEvent`).

## Options considered

1. **One provider's HTTP API and webhook format.** Richest data. Ties the code to a provider,
   which ADR 0017 and the owner rule out.
2. **A generic signed endpoint with our own contract** (chosen): HMAC-signed posts carrying a
   standard delivery status notification (RFC 3464 fields) or a small neutral JSON event. Any
   provider, or a forwarder in front of one, can feed it.
3. **Only parsing bounce emails at a bounce mailbox.** No webhook at all, and the inbound path
   exists. But it depends on the relay letting our envelope sender through, and DSN emails from
   unknown servers are slow and uneven. Kept as an optional fallback into the same processing.

## Decision

- **Endpoint:** `POST /inbound/email_events`, with `X-Shadetree-Timestamp` and
  `X-Shadetree-Signature` (`v1=` + hex HMAC-SHA256 over `<timestamp>.<body>`), keyed with a
  per-environment secret from the environment (at least 32 characters; without it the endpoint
  is not found). Refused: bad signatures, timestamps more than 5 minutes off, bodies over
  256 KB. Failed attempts are rate limited per IP, as on the support ingress.
- **Formats:** a delivery status notification (RFC 3464 fields) or our own strict, versioned
  JSON event, documented in a runbook. Both become one normalised event (id, type, Message-ID,
  reference, recipient, status and reply codes, time). App code names no provider.
- **Forwarder:** a provider that can't post our format gets a small forwarder, kept in `infra/`
  (ADR 0026). It verifies the provider's own signature and freshness before re-signing, uses
  each environment's own secret, and never logs addresses.
- **In the request:** verify, parse, then match and check the recipient. An event matches an
  `EmailMessage` by our Message-ID or its existing reference header (`X-Shadetree-Email`, the
  email's uid), and only if the recipient is its To or a CC on its send. Unmatched events and
  those more than 14 days after the email was sent are counted and dropped.
- **Stored, then enqueued:** once per event id (else a body digest): type, status code, reason
  category, time, the email and the recipient's role (To or CC). Never the address, diagnostic
  text or payload, in rows or logs. Rows are deleted after 90 days.
- **Processing:** the background job applies send time's rules through `EmailMessage#mark!`
  (mailbox statuses bounce and block the address; other permanent statuses fail without
  blaming it). The error carries a code `reply_code` can read, and a late event is never
  "our side". NTF-05 sets the product rules (CCs, complaints, answered or paid documents).
- **Fallback:** an optional bounce mailbox on the existing inbound-email path feeds parsed
  bounce emails into the same processing, only if the relay keeps our envelope sender.

## Consequences

- Late bounces show like send-time refusals; switching providers is configuration only.
- A relay may rewrite the Message-ID; the reference header covers that (owner, 2026-11-22).
- The lookup spans businesses (`Tenancy.across_businesses`), reviewed like any bypass.
- The relay keeps its own suppression list. Clearing an address in the app doesn't clear it
  there, so the operations runbook gets that step.
- New settings for PLT-09's list and the operations runbook: the endpoint secret, and the
  bounce address when the fallback is on. Each environment has its own secret.
- **Cost:** none at launch: one endpoint, a small table purged after 90 days, a background job
  per event. It grows with bounce volume, not with free-tier businesses.
