---
id: MKT-03
title: Legal & trust pages
domain: marketing
milestone: M5
depends_on: [PLT-05]
---
# MKT-03 · Legal & trust pages

> Requirements: [11-marketing](../../plans/11-marketing.md) R6

## Summary

We can't take money or process clients' personal data without clear terms. Publish the legal
and trust pages a small SaaS needs, wire acceptance into sign-up, and make updates traceable.

## User stories

- As a business owner, I want to know who owns my data and how it's protected before I sign up.
- As the founder, I want proof that each user accepted the terms in force when they signed up.

## Acceptance criteria

- [x] Pages exist for: Terms of Service, Privacy Policy, Acceptable Use Policy, a data
      processing summary (how we process businesses' client data on their behalf), a list of
      sub-processors, and a security/trust overview.
- [x] Each page shows an effective date and a change history; previous versions remain
      accessible.
- [x] Sign-up records which Terms/Privacy versions the user accepted and when (ACC-01 checkbox).
- [x] Material updates can prompt existing users to re-accept on next sign-in (mechanism
      exists; prompting is an operator decision).
- [x] Client-facing pages and emails link to the business's own contact details and to
      Shadetree's privacy policy where required.
- [x] A cookie notice appears only if non-essential cookies are used (goal: none).
- [x] Footer links to all legal pages from marketing, app and client layouts.

## Out of scope

- Writing the legal text itself (provided by the business owner/legal review).
- Per-business terms for their clients (that's quote/invoice terms in CAT-01).

## Decisions

- **Drafted in-house, marked as drafts** (owner's M5 answer: "draft legal text"): every page
  shows a notice that it's pending legal review until a reviewed version replaces it. The
  open questions below still block public launch.
- **No cookie notice**: Shadetree sets only cookies it needs to work (session, remember-me,
  this browser's id), and analytics are cookieless (MKT-04), so the notice never appears.
- **The first version isn't "material"**: people who signed up earlier accepted the placeholder
  terms and aren't asked again; later material versions are.

## Implementation notes

- `LegalDocument` lists the six pages (Terms, Privacy, Acceptable Use, Data Processing
  Summary, Sub-processors, Security & Trust) and their versions (effective date, summary,
  `material`, `draft`). Each version's text is its own view, never edited once published;
  `/legal/<slug>/<version>` keeps earlier ones readable (not indexed). Pages show the effective
  date and the change history.
- Sign-up (and sign-up through an invitation) records `terms_version` and `privacy_version`
  with `terms_accepted_at`. A material version in force sends people who accepted an older
  one to "We've updated our terms" on their next visit to the app; accepting records the new
  versions and carries on where they were going.
- Footers: a Legal column on the marketing site; Terms · Privacy · Legal under the user in the
  app; a Privacy link on client pages and a "How your details are handled" link in client
  emails, shown even when "Powered by Shadetree" is hidden.
- The sub-processor list names Stripe; hosting and email delivery are "to be named before
  launch". The text describes how Shadetree works once the in-flight M5 work (security
  baseline, sessions list, data export and erasure, operator audit log) is merged.

## Open questions

- **(blocking for public launch)** Source and legal review of the policy text
  (11-marketing open question 2).
- Which jurisdiction governs the terms (where is the company registered)?
