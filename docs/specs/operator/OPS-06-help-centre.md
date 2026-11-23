---
id: OPS-06
title: Help centre and knowledge base
domain: operator
milestone: M6
depends_on: [OPS-05, ACC-08, MKT-01]
---
# OPS-06 · Help centre and knowledge base

> Requirements: [10-operator](../../plans/10-operator.md) R17–R20

## Summary

Help today means asking Shadetree (support tickets, OPS-05) or replaying the tour (ACC-08).
Add a knowledge base beside them: how-to articles, with screenshots, for every workflow in the
app, written in plain words for people who run service businesses, not software. Articles live
in the repo next to the code, are written by the coding agent alongside each feature and
published with each deploy. Checks keep them complete and in step with the screens.

## User stories

- As an owner, I want to look up "how do I take tax off one invoice" and get an answer now.
- As an owner on the send page, I want "What will my client see?" right there, with a picture.
- As someone comparing tools, I want to read how Shadetree works before I sign up.
- As an operator, I want to answer a common question by linking an article.

## Acceptance criteria

- [ ] Each article is a Markdown file in the repo with front matter: title, summary, category,
      the help topics it answers, last reviewed date and its screenshots. Merged files go live
      with the next deploy; there is no editing in the console.
- [ ] Articles are public at `/help` (marketing layout, indexed, in the sitemap, MKT-04) and
      shown inside the app to signed-in members, in the app layout. No article holds private data.
- [ ] Categories follow the app's areas: Getting started, Requests, Quotes, Schedule & jobs,
      Invoices & payments, Settings & team, Plan & billing. Members and visitors browse by
      category and search by title and text, best matches first; an empty search suggests
      asking Shadetree (members) or contacting us (visitors).
- [ ] Help has three parts: articles, "Ask Shadetree for help" (OPS-05) and the tour and tips
      (ACC-08). The Help menu gains "Help articles" and a search box.
- [ ] Before a ticket is sent, the form shows up to three articles matching its subject or the
      page it came from. Opening one keeps the draft; the ticket can always still be sent.
- [ ] In-app pages show a "Learn more" link to the article for their help topic (the send page,
      Services & prices, Settings, the schedule, first-time tips). Operators can paste an
      article link into a ticket reply.
- [ ] Each article ends with "Was this helpful?" (yes/no counts per article, nothing about who);
      after a no it offers "Ask Shadetree". Searches with no results are counted by their words
      only (no person or business), kept 90 days, and listed for operators.
- [ ] Screenshots are generated, not hand-made: one task captures each declared screenshot from
      the demo seed data at fixed sizes (1280 and 390 wide) and fixed dates, and the images are
      committed. Nothing personal appears: only demo businesses and clients.
- [ ] CI fails when: a page links to an undeclared help topic; a declared topic has no article
      (coverage); an article links to a missing article or image; or a screen a screenshot shows
      has changed since it was captured. That last one is the review trigger: the PR that changes
      the screen recaptures its screenshots and re-reads the article (updating last reviewed).
- [ ] Articles read well at 360 px and with a screen reader; images have alt text describing
      the step; the axe check passes.
- [ ] Tests cover rendering (no raw HTML or scripts), search, ticket-form suggestions, "Learn
      more" links, feedback and no-result counts, public and in-app access, CI checks, mobile.

## Writing guide

- Speak the reader's language: plain words, no jargon ("your client", not "contact record").
- Start from the task ("Send a quote by text"), then the steps, one action each, with a picture.
- Answer the worries behind the question: getting paid, looking professional to clients, and
  undoing a mistake ("Sent the wrong price? Here's how to fix it, and what your client sees").
- Be thorough about what happens next and who sees what, without padding; short paragraphs.

## Out of scope

- Videos, live chat, forums, AI answers, translations, articles by businesses (backlog). A help
  centre for a business's own clients (OPS-05 decision).

## Decisions

- Help offers support tickets and a knowledge base that grows with the application (owner,
  2026-11-22). This reverses 10-operator D5 and the vision's "no knowledge base at launch".
- Articles are Markdown files in the repo, written by the coding agent alongside each feature,
  best effort, so users have every answer they need to decide with confidence; published by
  deploy, with generated screenshots (owner, 2026-11-22).
- Public at `/help` and in the app; categories, no-result counts and "Was this helpful?" as
  above; an article is reviewed whenever a release changes a screen it shows (owner, 2026-11-22).
- Every workflow gets an article; the PR checklist asks "Does this change a screen an article
  describes?" (owner, 2026-11-22).

## Implementation notes

- Search stays simple: on deploy (and in dev on boot) the article files are loaded into a table
  searched with PostgreSQL full-text search, title weighted above text. No search service.
- Screenshot fingerprints: the capture task stores a digest of each captured region's markup
  (volatile text removed) beside the image; CI recomputes it to spot a changed screen.
- Today's Help: the Help menu in `app/views/layouts/app.html.erb`, the ticket form
  `app/views/admin/support_tickets/new.html.erb` (it passes `from:` the page), `/admin/help` and
  the `/help` redirect in `config/routes.rb`. Tour and tips: `GuidedTour`, `FirstTimeTips`,
  `config/locales/guidance.en.yml`. Repo-kept pages precedent: `LegalDocument` (MKT-03).
  Demo data: `db/seeds/development.rb`; screenshots as in system tests (Capybara, Chrome).

## Open questions

- None. The owner answered them on 2026-11-22.
