# Late bounces and complaints (NTF-05)

Most mail relays accept any well-formed address and only learn later that the client's server
refused it. Those late reports reach the app at one generic, signed endpoint
([ADR 0028](../adr/0028-generic-bounce-event-endpoint.md)). The app still sends over plain SMTP
and names no email provider: whatever posts here (the relay itself, or a forwarder in front of
it) must speak this contract.

## The endpoint

`POST /inbound/email_events`, one report per request.

| Header | Value |
| --- | --- |
| `X-Shadetree-Timestamp` | Unix seconds when the post was signed |
| `X-Shadetree-Signature` | `v1=` + hex HMAC-SHA256 of `<timestamp>.<raw body>`, keyed with `EMAIL_EVENTS_SECRET` |
| `Content-Type` | `application/json` for our JSON event; anything else is read as a delivery status notification |

```
ts=$(date +%s)
sig=$(printf '%s.%s' "$ts" "$(cat event.json)" | openssl dgst -sha256 -hmac "$EMAIL_EVENTS_SECRET" -r | cut -d' ' -f1)
curl -X POST https://staging.getshadetree.com/inbound/email_events -H 'Content-Type: application/json' \
  -H "X-Shadetree-Timestamp: $ts" -H "X-Shadetree-Signature: v1=$sig" --data-binary @event.json
```

Answers: `204` taken (stored, a repeat, or counted and dropped); `401` bad or missing signature,
or a timestamp more than 5 minutes off; `413` over 256 KB; `422` signed but not one of the two
formats; `429` too many failed attempts (401 or 413) from this IP in a minute; `404` the app has no
`EMAIL_EVENTS_SECRET` (or one shorter than 32 characters). Retry only on `429` and `5xx`.

The rate limit counts failures per IP, not per sender. If the relay or forwarder posts from a
shared egress address (a cloud provider's, or behind a tunnel), someone else's bad posts from
that address can trip the limit for the real sender for a minute; a sender that retries
delivers its reports once the minute is over.

## Formats

**Our JSON event, version 1.** Strict: an unknown key, another version, or a value of the wrong
shape refuses the whole post (`422`).

```json
{
  "version": 1,
  "id": "the sender's own event id (optional; without it, a digest of the body is used)",
  "type": "bounce",
  "message_id": "<the email's Message-ID>",
  "reference": "the email's X-Shadetree-Email header",
  "recipient": "the address that bounced or complained (optional for a complaint)",
  "status": "5.1.1",
  "reply_code": "550",
  "occurred_at": "2026-11-23T15:04:05Z"
}
```

`type` is `bounce`, `complaint` (marked as spam) or `delay`. Every event needs `message_id` or
`reference`; a bounce or delay needs `status` (an enhanced status code, `5.1.1`); `reply_code` is
the 3-digit SMTP code when there is one. All values are strings except `version`.

**A delivery status notification** (RFC 3464): the `multipart/report` email itself, with its
`message/delivery-status` part (one block per recipient: `Final-Recipient` or
`Original-Recipient`, `Action`, `Status`, `Diagnostic-Code`, `Last-Attempt-Date`) and the returned
headers of our email (`text/rfc822-headers` or `message/rfc822`). Each `failed` recipient is a
bounce; `delayed` ones are delays.

## What the app does with it

In the request, an event is matched to a client email by its Message-ID or by the
`X-Shadetree-Email` reference header (relays may rewrite the Message-ID), and only if the
recipient is that email's To or one of the CCs it was sent with. Unmatched events, other
recipients, events more than 14 days after the email was sent, delays and temporary (`4.x.x`)
statuses are counted and dropped. The rest are stored once (by `id`, else a digest of the body),
without the address, the server's text or the payload, and processed in the background. Rows go
after 90 days. The operator console's home shows the last 7 days' counts ("Email events").

Log lines (`email_events.received`, `email_events.rejected`) carry outcomes and reasons only.

## Settings

- `EMAIL_EVENTS_SECRET` (secret, per environment, at least 32 characters, `openssl rand -hex 32`).
  Without it the endpoint answers `404`. Set it on each GitHub environment and redeploy.
- Staging sits behind Cloudflare Access: `/inbound/` is already on the bypass application.
- Rotating: change the sender's copy and the app's within minutes; reports signed with the old
  secret in between are refused, and a sender that retries delivers them again.

## The relay's own suppression list

The relay keeps its own list of addresses it won't send to. Clearing a blocked address in the app
(the client's page) doesn't clear it there: remove it from the relay's suppression list too, or
the next email is dropped by the relay and may never be reported.

## Feeding the endpoint

A relay that can post this contract is pointed at the endpoint with the environment's secret.
The relay configured in `infra/` can't. A forwarder for it, a small Worker like
`infra/support-email-worker` that verifies the relay's own signature and freshness, re-signs with
the environment's secret and never logs addresses, can be built, but it's deferred
(owner, 2026-11-24). **Until a relay or forwarder posts this format, late bounces and complaints
stay unhandled in production**: only refusals at send time are seen.
