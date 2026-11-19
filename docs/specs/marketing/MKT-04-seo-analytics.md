---
id: MKT-04
title: SEO, performance & analytics
domain: marketing
milestone: M5
depends_on: [MKT-01]
---
# MKT-04 · SEO, performance & analytics

> Requirements: [11-marketing](../../plans/11-marketing.md) R7, R8, R9

## Summary

Make the marketing site discoverable and fast, keep private surfaces out of search engines, and
measure the funnel from visit to sign-up to first quote sent — without invasive tracking or a
cookie banner.

## User stories

- As a prospect searching "quote software for cleaners", I want to find Shadetree.
- As the founder, I want to know how many visitors sign up and how many send a first quote.

## Acceptance criteria

- [x] Every marketing page has a unique title, meta description, canonical URL, and social share
      (Open Graph/Twitter) metadata with a share image.
- [x] A sitemap lists public marketing pages; robots rules and page metadata keep the staff app,
      operator console and client links out of search engines. Business request pages are
      indexable only if the business opts in (see open question).
- [ ] Marketing pages score ≥ 90 on mobile Lighthouse in performance, accessibility, best
      practices and SEO; a CI or scheduled check guards against regressions.
- [ ] Privacy-respecting analytics (no cross-site cookies, no personal data) record page views
      and key events: sign-up started, sign-up completed, business created, first quote sent.
- [ ] Analytics are disabled in development/test and never load on client-facing pages.
- [ ] A simple funnel view (in the analytics tool) shows visit → sign-up → first quote sent.
- [x] Structured data for the organization/software product is present.

## Out of scope

- Content marketing, ads tracking pixels, A/B testing (not planned).

## Decisions

- **Analytics: Plausible, self-hosted** (owner's choice, M5 planning): cookieless, no personal
  data, so no banner.
- **Business request pages are indexable only by choice**, per business, default off
  (recommendation accepted).

## Implementation notes

Part 1 (search engines):
- `page_meta description:` in each public view; the marketing layout adds the description,
  canonical address (public host from the mailer's URL options, no query string), Open Graph
  and Twitter cards with `marketing/share.png` (1200×630 JPEG, rendered from
  `docs/marketing/share-image.html` with headless Chrome). Titles and
  descriptions are unique per page (tested). A page without `page_meta` is noindex. The public
  host is `APP_HOST`, else the mailer's.
- `/robots.txt` and `/sitemap.xml` come from `SeoController`: robots disallow the staff app,
  account pages (sign-in and sign-up allowed), invitations and client links (the operator
  console answers "not found", so it isn't named); the sitemap lists the marketing and legal
  pages and request pages whose business ticked "Let search engines find this page"
  (Settings → Request form). The staff app also sends `X-Robots-Tag: noindex`; client pages are
  noindex; account pages other than sign-in and sign-up are noindex.
- The home page carries Organization and SoftwareApplication structured data, its offers from
  the listed plans.

## Open questions

- None.
