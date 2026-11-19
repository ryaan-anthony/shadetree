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
  this browser's id), and MKT-04's analytics will be cookieless, so the notice never appears.
  The policy doesn't mention analytics until MKT-04 ships.
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
  The prompt is the staff app's (`Admin::BaseController`) gate: a JSON lookup, frame or XHR gets
  a 403 and nothing is saved; a form post goes to the prompt without a return path. The account,
  sessions and sign-out pages stay reachable on purpose (someone who won't accept can still
  delete their account); the operator console has its own sign-in.
- Footers: a Legal column on the marketing site; Terms · Privacy · Legal under the user in the
  app; "Privacy (Shadetree)" on client pages and "How your details are handled" in client
  emails, both to the Privacy Policy's section for clients of a business (`#clients`), shown
  even when "Powered by Shadetree" is hidden.
- Requests go to mailboxes, not the contact form (which doesn't deliver yet):
  privacy@getshadetree.com, legal@getshadetree.com and security@getshadetree.com must exist
  before launch.
- Retention as written assumes PLT-09's backups: daily for 30 days, monthly for 12 months. Its
  file backup must also stop keeping deleted files beyond that (open question below).
- Promises are limited to what's built: no analytics until MKT-04; staff access is logged and
  needs two-factor through the support tools (OPS-01); a sole owner closes a business by
  contacting us.
- The sub-processor list names Stripe; hosting and email delivery are "to be named before
  launch". The text describes how Shadetree works once the in-flight M5 work (security
  baseline, sessions list, data export and erasure, operator audit log) is merged.

## Open questions

- PLT-09 (#134) syncs files to the backup bucket without `--delete`, so deleted photos and
  attachments would stay forever, against the 12-month promise. Add `--delete` with a
  12-month noncurrent-version expiry on the bucket, or change the text?
- The sub-processor list must name the email provider, which the codebase doesn't. Allow the
  name on this page, or render the list from configuration?

- **(blocking for public launch)** Source and legal review of the policy text
  (11-marketing open question 2).
- Which jurisdiction governs the terms (where is the company registered)?
