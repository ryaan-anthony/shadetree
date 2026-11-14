# 0011. Postmark for transactional email

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** NTF-01, ACC-01, ACC-03, QTE-04, PAY-02, JOB-05

## Context

Quotes, invoices and visit confirmations reach clients by email. An email in spam is a lost job.
NTF-01 needs authenticated sending from a platform domain, the business's address as reply-to,
and delivery events (delivered, bounced, complained) to suppress bad addresses. Volume at launch
is low; the free tier must not make email expensive.

## Options considered

1. **Amazon SES.** Cheapest per message (about $0.10 per 1,000). But it takes more setup and
   needs reputation management, and event handling has to be built with SNS.
2. **SendGrid or Mailgun.** Full-featured, but marketing-oriented, with shared-IP reputation
   that varies.
3. **Resend.** Simple API and a free tier, but younger, with less deliverability history.
4. **Postmark.** Transactional-only and known for deliverability. It has separate message streams
   (transactional vs. broadcast), simple bounce and complaint webhooks, and an Action Mailer
   adapter.

## Decision

Use **Postmark** through Action Mailer, on a platform sending domain with SPF, DKIM and DMARC.
Client-facing mail uses a transactional stream with the business name as the sender display
name and the business's email as reply-to (NTF-01). Delivery webhooks feed bounce suppression.
Development uses letter_opener-style previews; staging uses Postmark's sandbox or an allow-list.

Mail goes through Action Mailer only, so switching to SES later is a configuration change plus
a webhook adapter.

## Consequences

- One dependency for a critical path. We keep provider-specific code to the delivery adapter
  and the webhook endpoint.
- Domain DNS setup is part of PLT-09 and NTF-01 and depends on the brand/domain decision (G8).
- **Cost:** about $15/month for 10,000 emails, enough for hundreds of active businesses. Revisit
  SES if volume grows past ~50,000 a month.
