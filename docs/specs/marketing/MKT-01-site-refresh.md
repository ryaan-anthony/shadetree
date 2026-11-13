---
id: MKT-01
title: Marketing site refresh
domain: marketing
milestone: M5
depends_on: [PLT-05, BIL-01]
---
# MKT-01 · Marketing site refresh

> Requirements: [11-marketing](../../plans/11-marketing.md) R1–R4, R10

## Summary

Rework the existing marketing pages around the new positioning: simple, affordable quoting,
scheduling and payments for small service crews, free to start. One clear call to action, real
product screenshots, and pricing that can never drift from what the app enforces.

## User stories

- As a skeptical lawn-care owner, I want to understand in five seconds what this does and that
  I can start free.
- As a prospect comparing tools, I want honest pricing with no "contact sales".

## Acceptance criteria

- [ ] Home page: headline and subhead on the core loop, a visual of quote → approve → schedule →
      paid, who it's for (industries), a pricing teaser, and a single primary CTA ("Start free")
      repeated at natural points.
- [ ] Features page covers quoting, client approval, scheduling and technician view, invoicing
      and payments, with real screenshots from the product (not mockups).
- [ ] Pricing page renders plans, prices, limits and features from plan data (BIL-01) and
      includes an FAQ (limits, what happens at the limit, cancellation, data export).
- [ ] About page tells the real story of who builds Shadetree; contact page is kept (MKT-02).
- [ ] Navigation and footer are consistent; footer links to legal pages (MKT-03).
- [ ] No fabricated metrics, logos or testimonials; placeholders are removed.
- [ ] All pages use the marketing layout (PLT-05) and work at 360 px.
- [ ] Copy is reviewed for plain language; system tests cover page rendering and CTA paths.

## Out of scope

- SEO metadata and analytics (MKT-04). Industry pages, blog, help center (backlog).

## Open questions

- **(blocking)** Product name and domain (G8).
- Who provides final copy and screenshots? Recommend drafting copy in the PR and taking
  screenshots from staging seeded data near launch.
