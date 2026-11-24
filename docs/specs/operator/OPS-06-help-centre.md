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

Beside support tickets (OPS-05) and the tour (ACC-08), add a knowledge base: how-to articles
with screenshots for every workflow, in plain words for people who run service businesses. They
live in the repo, are written by the coding agent with each feature and go live with each
deploy; checks keep them complete and in step with the screens.

## User stories

- As an owner, I want to look up "how do I take tax off one invoice" and get an answer now.
- As an owner on the send page, I want "What will my client see?" right there, with a picture.

## Acceptance criteria

- [x] Each article is a Markdown file in the repo with front matter: title, summary, category,
      help topics, last reviewed date and screenshots. It goes live with the next deploy; there
      is no editing in the console.
- [x] Public at `/help` and `/help/<slug>` (marketing layout, indexed, in the sitemap). Members
      read them in the app at `/admin/help/articles/<slug>` (app layout, `noindex`, canonical
      link to the public copy); `/admin/help` stays the ticket list. `/help` no longer redirects
      to `/admin/help`; a signed-in member at `/help…` lands on the in-app copy.
- [x] Categories: Getting started; Clients & requests; Quotes; Schedule & jobs (with My day);
      Invoices & payments; Services & prices; Settings & team; Plan & billing. Browse by
      category; search by title and text, best first. No results suggests asking Shadetree
      (members) or contacting us (visitors).
- [x] Before a ticket is sent, the form shows up to three articles matching its subject or its
      `page` (the hidden field holding `from:`). Opening one keeps the draft; it can still be sent.
- [x] The Help menu gains "Help articles" and a labelled search box (`role="search"`). Pages
      show "Learn more" to their topic's article (send page, Settings, schedule, first-time tips).
- [x] "Was this helpful?" counts yes/no per article, nothing about who; after a no, members get
      "Ask Shadetree" and visitors "Contact us" (the marketing contact page). No-result searches
      are counted by words only: at most 100 characters, anything like an email or phone number
      dropped, kept 90 days, escaped in the operators' list. Votes and counts are rate limited.
- [x] Markdown is rendered safely: raw HTML off, http(s) and relative links only, no style
      attributes (the CSP allows only our stylesheets), images only from the help image folder.
      Slugs match `[a-z0-9-]+` and are looked up in the loaded index, never used as file paths.
- [x] Screenshots are generated: one command captures each declared screenshot from the demo
      seed data at 1280 and 390 wide, in CI's environment, as WebP under 200 KB, and commits them.
      Only demo businesses and clients appear.
- [x] CI fails when a page uses an undeclared help topic, a topic has no article (coverage), an
      article links to a missing article or image, or a screen in a screenshot has changed
      since capture; the message names the recapture command. That is the review trigger: the
      PR that changes a screen recaptures it and re-reads the article (updating last reviewed).
- [x] AGENTS.md says "write or update the help article with each feature"; the PR template's
      checklist gains "Does this change a screen an article describes?".
- [ ] Articles work at 360 px and with screen readers; alt text says what to do; axe passes.
- [ ] Tests cover rendering safety, both copies, search, suggestions, "Learn more", votes and
      counts with limits, the CI checks and mobile.

## Writing guide

- Not technical: plain words, the app's exact button labels, no jargon. Task first ("Send a
  quote by text"), then one action per step, each with a picture.
- Empathy for the questions behind the question: getting paid, looking professional to
  clients, undoing a mistake ("Sent the wrong price? Here's the fix, and what your client sees").
- Thorough about what happens next and who sees what, without being verbose.

## Out of scope

- Videos, chat, forums, AI answers, translations; help for a business's own clients (OPS-05).

## Decisions

- Help offers tickets and a knowledge base that grows with the app, reversing 10-operator D5
  and the vision's "no knowledge base at launch" (owner, 2026-11-22).
- Articles in the repo, by the coding agent, best effort, so non-technical users can make
  confident decisions; with screenshots; thorough without being too verbose; every workflow;
  the PR checklist line; public and in the app; no-result counts and "Was this helpful?";
  review whenever a release changes a screen an article shows (owner, 2026-11-22).
- The eight categories (owner, 2026-11-23).
- In-app path, canonical and `noindex` (follows `/admin` for staff pages); rendering rules
  (follows the CSP); limits and scrubbing (follows `rate_limit` and `Observability.scrub`);
  sizes and WebP (follows the 360 px rule and `image_processing`).

## Implementation notes

- Rendering: Commonmarker (GitHub-flavoured Markdown, unsafe HTML off), links and images
  checked against the allow list; front-matter image paths validated when articles load.
- Loading: at boot, an idempotent upsert of the files into a table (removed files deleted),
  searched with PostgreSQL full-text search, title weighted above text. No search service.
- Screen digest, without Chrome: the rendered HTML of the captured region (Nokogiri), with
  volatile parts removed (uids, CSRF tokens, nonces, asset digests, times and dates).
- As built: articles in `content/help/articles/<slug>.md`, images in `app/assets/images/help`;
  `HelpCentre` loads and checks them, `HelpCentre::Markdown` renders, `HelpArticle.sync!` stores.
- No-result searches typed into the app's list aren't counted (a pause mid-word would count).

## Open questions

- None. The owner answered them on 2026-11-22 and 2026-11-23.
