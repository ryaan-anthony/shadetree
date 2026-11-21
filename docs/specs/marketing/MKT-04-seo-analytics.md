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
- [x] Privacy-respecting analytics (no cross-site cookies, no personal data) record page views
      and key events: sign-up started, sign-up completed, business created, first quote sent.
- [x] Analytics are disabled in development/test and never load on client-facing pages.
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
- While requests are off, that setting is disabled and the server ignores it: it keeps its saved
  value, so turning requests back on restores the business's choice (QA #274).
- The home page carries Organization and SoftwareApplication structured data, its offers from
  the listed plans.

Part 2 (analytics and speed):
- `Analytics` (Plausible, self-hosted): set `ANALYTICS_HOST` and `ANALYTICS_DOMAIN` in
  production; off in development and test (`config.x.analytics`). The script loads on the
  marketing layout only. The app's funnel steps are sent from the server by
  `AnalyticsEventJob`: "Sign-up Completed", "Business Created" and "First Quote Sent" (the business's
  first), each with a fixed address and no ids, plus the visitor's browser and IP so Plausible
  links them to the same anonymous visitor. A failed send is logged and dropped.
- In Plausible: add the goals Pageview `/users/sign_up` ("Sign-up started") and the three
  custom events. Self-hosted Plausible (Community Edition) shows each goal's conversions but
  has no funnel view, and its visitor ID changes daily, so steps on later days aren't linked:
  the funnel criterion is open (see Open questions).
- The script loads only on pages that opt in (`content_for :analytics`): the marketing pages
  and sign-up, never invitation or account pages (tokens and private paths). The CSP (PLT-13,
  #195) must allow `ANALYTICS_HOST` in `script-src` and `connect-src`; whichever of the two
  merges second adds it. The privacy policy (MKT-03) describes it.
- Speed: screenshots come with half-size versions (`srcset`), one low-contrast label is fixed.
  Measured on a development server (no compression, unminified): 87–89 performance, 100 for
  accessibility, best practices and SEO; production adds compression (Cloudflare, ADR 0023).
  `script/lighthouse_check URL` checks the pages (90 or more in every category), and the
  Lighthouse workflow runs it weekly against `MARKETING_URL` once that variable is set. The
  criterion is ticked once that run passes against the live site.

## Open questions

- **The funnel view**: self-hosted Plausible has no funnels. Options: show per-goal
  conversions only (Community Edition), Plausible Cloud's Business plan (then a sub-processor),
  a self-hosted tool with funnels (Umami), or a funnel in the operator console from the app's
  own data (`first_quote_sent_at` and friends).
