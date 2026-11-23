---
id: OPS-06
title: Help centre and knowledge base
domain: operator
milestone: M6
depends_on: [OPS-05, ACC-08, OPS-01]
---
# OPS-06 · Help centre and knowledge base

> Requirements: [10-operator](../../plans/10-operator.md) R17–R20

## Summary

Help today means asking Shadetree (support tickets, OPS-05) or replaying the tour (ACC-08).
Add a knowledge base beside them: short how-to articles that operators write in the console,
that members can browse and search, that appear next to the screen they explain, and that are
offered before a ticket is filed. It grows with the app, and checks keep it from going stale.

## User stories

- As an owner, I want to look up "how do I take tax off one invoice" and get an answer now,
  without waiting for a reply.
- As an owner on the send page, I want a "How sending works" link right there.
- As an operator, I want to answer a common question once, in an article, and link it from replies.
- As an operator, I want to know which articles are missing or out of date when the app changes.

## Acceptance criteria

- [ ] Help has three parts: articles, "Ask Shadetree for help" (OPS-05) and the tour and tips
      (ACC-08). The Help menu gains "Help articles" and a search box; the Help page leads with them.
- [ ] Operators write articles in the console: title, summary, body in Markdown (headings,
      lists, links, images, callouts; no raw HTML or scripts), category, related articles, a
      published or draft state and a live preview. Every save and publish is in the audit log
      (OPS-01); each published version is kept, viewable and restorable.
- [ ] Images are uploaded through the console, re-encoded without metadata, and the editor
      reminds the writer to use demo data only (no client or member details).
- [ ] Members browse articles by category and search them by title and text; results show
      title and summary, best matches first. An empty search suggests asking Shadetree.
- [ ] Before a ticket is sent, the form shows up to three articles that match its subject or the
      page it came from. Opening one keeps the draft; the ticket can always still be sent.
- [ ] In-app pages can show a contextual "Learn more" link to a named article (the send page,
      Services & prices, Settings, the schedule, first-time tips). A link whose article isn't
      published is not shown, so members never reach a missing page.
- [ ] Keeping in step: every contextual link names a help topic declared in one place in the
      code, and an automated check fails CI if a page uses an undeclared topic. The console lists
      declared topics with no published article, articles past their review date, and links
      between articles that point at an unpublished one (publishing is refused until fixed).
- [ ] Operators can mark an article reviewed, and link an article in a ticket reply.
- [ ] Articles read well at 360 px and with a screen reader; the axe check passes.
- [ ] Tests cover authoring and audit, versions and restore, search, suggestions on the ticket
      form, contextual links (published and not), the topic check, access rules and mobile.

## Out of scope

- Videos, live chat, community forums, AI answers, translations (backlog).
- A helpdesk or knowledge base for a business's own clients (OPS-05 decision).
- Articles written by businesses.

## Decisions

- Help offers support tickets and a knowledge base that grows with the application (owner,
  2026-11-22). This reverses 10-operator D5 and the vision's "no knowledge base at launch".
- Operators write the articles in the console (owner, 2026-11-22).

## Implementation notes

- Today's Help: the Help menu in `app/views/layouts/app.html.erb` (`data-tour="help"`), the
  ticket form `app/views/admin/support_tickets/new.html.erb` (it already passes `from:` the page),
  `/admin/help` and the `/help` redirect in `config/routes.rb` ("a public help center may live
  here one day"). Tour and tips: `GuidedTour`, `FirstTimeTips`, `config/locales/guidance.en.yml`.
- Console: `app/views/layouts/ops.html.erb` nav; plans, presets and flags show the console's
  form pattern; audit through `AuditEntry` (`article.*`). Ticket replies: `Ops::TicketsController`.
- Versioned text kept in the repo already exists for legal pages (`LegalDocument`, MKT-03).

## Open questions

- **(blocking)** Where articles live. Recommend the database (Markdown, a version per publish)
  so operators publish without a deploy, as the owner's "written in the console" implies; topics
  for contextual links stay declared in code so CI can check them. The alternative, Markdown
  files in the repo, gets review and CI checks for free but needs a developer to publish.
- **(blocking)** Who can read them. Recommend public at `/help` (marketing layout, indexed, MKT-04)
  for published articles, also shown inside the app to members; nothing in them is private.
  Staff-only would keep `/help` as a sign-in redirect.
- Categories. Recommend the app's areas, as the tour's stops: Getting started, Requests,
  Quotes, Schedule & jobs, Invoices & payments, Settings & team, Plan & billing.
- Search terms. Recommend counting searches that found nothing (the words only, no person or
  business, kept 90 days) so operators see what to write next.
- "Was this helpful?" Recommend yes/no counts per article, with "Ask Shadetree" after a no.
- Review period. Recommend 6 months, and also whenever a release touches the area an
  article's category covers.
- Starting content. Recommend about ten articles at launch, one per category plus sending and
  getting paid, and a PR checklist line: "Does this change a screen an article describes?"
