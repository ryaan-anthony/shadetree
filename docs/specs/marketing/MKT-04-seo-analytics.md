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

- [ ] Every marketing page has a unique title, meta description, canonical URL, and social share
      (Open Graph/Twitter) metadata with a share image.
- [ ] A sitemap lists public marketing pages; robots rules and page metadata keep the staff app,
      operator console and client links out of search engines. Business request pages are
      indexable only if the business opts in (see open question).
- [ ] Marketing pages score ≥ 90 on mobile Lighthouse in performance, accessibility, best
      practices and SEO; a CI or scheduled check guards against regressions.
- [ ] Privacy-respecting analytics (no cross-site cookies, no personal data) record page views
      and key events: sign-up started, sign-up completed, business created, first quote sent.
- [ ] Analytics are disabled in development/test and never load on client-facing pages.
- [ ] A simple funnel view (in the analytics tool) shows visit → sign-up → first quote sent.
- [ ] Structured data for the organization/software product is present.

## Out of scope

- Content marketing, ads tracking pixels, A/B testing (not planned).

## Open questions

- Analytics tool choice — must not require a cookie banner (11-marketing open question 3).
- Should business request pages be indexable (local SEO benefit for businesses)? Recommend a
  per-business toggle, default off.
