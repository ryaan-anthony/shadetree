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

The app exposes one inbound bounce-event endpoint. A post is accepted only with a valid
`v1=` HMAC-SHA256 over `<timestamp>.<body>`, keyed with a secret from the environment (at least
32 characters; without it the endpoint is not found), within 5 minutes, under a size cap, with
failed attempts rate limited per IP as on the support ingress. The body is either a delivery
status notification or our versioned JSON event; both become the same normalised event (id,
type, Message-ID, reference, recipient, status code, time). Events are stored once (by event id, else a
digest of the body) and processed in the background. An event matches an `EmailMessage` by our
Message-ID or reference header, and only if its recipient is one the email went to; permanent failures go through
`EmailMessage#mark!` with send time's rules (mailbox statuses bounce and suppress, other
permanent statuses fail without blaming the address), so the existing warning, timeline,
notification and Resend follow. Only ids, type, status code, a reason category and times are
kept; diagnostic text, addresses and payloads are never stored or logged. An optional bounce
mailbox on the existing inbound-email path feeds parsed DSN emails into the same processing.

## Consequences

- Late bounces show like send-time refusals; switching providers is configuration only.
- A provider that can't sign our way needs a small forwarder, kept as configuration in `infra/`
  (ADR 0026), not in the app.
- A relay may rewrite the Message-ID, so each client email also carries an opaque reference
  header, and an event matches on either (owner, 2026-11-22).
- The lookup by Message-ID spans businesses (`Tenancy.across_businesses`), reviewed like any bypass.
- New settings for PLT-09's list and the operations runbook: the endpoint secret, and the
  bounce address when the fallback is on. Each environment has its own secret.
- **Cost:** none at launch: one endpoint, a small table purged after 90 days, a background job
  per event. It grows with bounce volume, not with free-tier businesses.
