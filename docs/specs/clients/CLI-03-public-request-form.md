---
id: CLI-03
title: Public request form
domain: clients
milestone: M2
depends_on: [CLI-01, CAT-02, CAT-03, NTF-01]
---
# CLI-03 · Public request form

> Requirements: [04-clients](../../plans/04-clients.md) R9–R13

## Summary

Give each business a branded, shareable page where prospective clients ask for work — choosing
services, describing the job, adding photos — so leads stop getting lost in voicemail and text
threads. Each submission becomes a client (or matches one) and a request in the inbox.

## User stories

- As a homeowner, I want to request a quote from my phone in under two minutes without making
  an account.
- As an owner, I want one link to put on my website, Google profile and Facebook page.
- As an owner, I want to be notified immediately when a request comes in.

## Acceptance criteria

- [x] Each business has a public request page at a stable, human-friendly URL (based on a
      unique business handle editable by Owners/Admins); it uses the client-facing layout and
      branding. *`/request/<handle>`, defaulting to the business name.*
- [x] The form collects name, email and/or phone, service address, interested services
      (multi-select from active catalog items flagged for the form; optional), description,
      preferred timing (free text or simple options), and photos (limited count/size). *Timing
      is three simple options; up to 5 photos of 10 MB, re-encoded without metadata.*
- [x] Submitting creates a request linked to a new or matched client (matched on email/phone
      within the business only) and property; nothing is merged destructively. *Active
      clients only, email before phone. A match is linked to its property at that address if
      it has one, and gets nothing typed added; the request keeps what was typed.*
- [x] The submitter sees a branded confirmation; an acknowledgment email is sent if an email was
      given; the business receives a "new request" notification (email now, in-app via NTF-02).
      *The acknowledgment repeats nothing the person typed, and counts toward the hourly limit.*
- [x] Owners/Admins can turn the form on/off and set intro text; when off, the page shows contact
      details instead.
- [x] Settings show the link with copy and a QR code download.
- [x] Spam protection is invisible to normal users; excessive submissions are rate limited.
      *Hidden field, minimum 3 s on the page, 5 per IP per 10 minutes, 60 per business per hour.*
- [x] The page is fast on mobile (≥ 90 Lighthouse) and accessible. *97–99 and 100 via Thruster.*
- [x] Tests cover matching, disabled form, spam rejection and tenant isolation.

## Out of scope

- Inbox/triage (CLI-04). Embeddable widget, custom questions, service-area checks (backlog).

## Open questions

- ~~Require email, phone, or either?~~ Either, with email encouraged. Spam protection is a
  hidden field, a minimum time on the page and rate limits, with no third-party CAPTCHA.
- ~~Should photo limits differ by plan?~~ Owned by BIL-01; a fixed limit (5 photos, 10 MB
  each) until then.
