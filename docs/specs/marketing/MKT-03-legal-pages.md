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

- [ ] Pages exist for: Terms of Service, Privacy Policy, Acceptable Use Policy, a data
      processing summary (how we process businesses' client data on their behalf), a list of
      sub-processors, and a security/trust overview.
- [ ] Each page shows an effective date and a change history; previous versions remain
      accessible.
- [ ] Sign-up records which Terms/Privacy versions the user accepted and when (ACC-01 checkbox).
- [ ] Material updates can prompt existing users to re-accept on next sign-in (mechanism
      exists; prompting is an operator decision).
- [ ] Client-facing pages and emails link to the business's own contact details and to
      Shadetree's privacy policy where required.
- [ ] A cookie notice appears only if non-essential cookies are used (goal: none).
- [ ] Footer links to all legal pages from marketing, app and client layouts.

## Out of scope

- Writing the legal text itself (provided by the business owner/legal review).
- Per-business terms for their clients (that's quote/invoice terms in CAT-01).

## Open questions

- **(blocking for public launch)** Source and legal review of the policy text
  (11-marketing open question 2).
- Which jurisdiction governs the terms (where is the company registered)?
