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

- [x] Home page: headline and subhead on the core loop, a visual of quote → approve → schedule →
      paid, who it's for (industries), a pricing teaser, and a single primary CTA ("Start free")
      repeated at natural points.
- [x] Features page covers quoting, client approval, scheduling and technician view, invoicing
      and payments, with real screenshots from the product (not mockups).
- [ ] Pricing page renders plans, prices, limits and features from plan data (BIL-01) and
      includes an FAQ (limits, what happens at the limit, cancellation, data export).
- [ ] About page tells the real story of who builds Shadetree; contact page is kept (MKT-02).
- [x] Navigation and footer are consistent; footer links to legal pages (MKT-03).
- [ ] No fabricated metrics, logos or testimonials; placeholders are removed.
- [ ] All pages use the marketing layout (PLT-05) and work at 360 px.
- [ ] Copy is reviewed for plain language; system tests cover page rendering and CTA paths.

## Out of scope

- SEO metadata and analytics (MKT-04). Industry pages, blog, help center (backlog).

## Decisions

- **Name and domain**: Shadetree, getshadetree.com (G8 settled). **Copy is drafted in the PRs**
  and screenshots taken from seeded data (recommendation accepted, M5 planning).
- **The site only promises what's built.** Online card payments (PAY-03/04) and automatic
  follow-ups (NTF-04) aren't mentioned until they ship; plans aren't described as "never per
  seat" because they limit team members.

## Implementation notes

Part 1 (layout and home):
- One navigation (logo, How it works, Features, Pricing, About, Sign in, Start free) that folds
  into a script-free menu on phones, and one footer (Product, Company, Legal). The old top bar
  and its language picker, which did nothing, are gone.
- Home follows `docs/mockups/marketing/home.html`: the loop as the headline, the product doing
  it (drawn in the app's own styles), the industries from `config/industries.yml`, the four
  steps, quotes and crew sections, a pricing teaser from `Plan.listed` (prices and quotas can't
  drift: `MarketingHelper`), three promises, and a closing "Start free" box that carries the
  email into sign-up.

Part 2 (Features and About):
- Features: quoting, client approval, scheduling, the crew's phone and invoicing, each beside a
  real screenshot in `app/assets/images/marketing/` (WebP, each under 120 KB, sized and lazily
  loaded, with alt text that says what's on screen). They were taken from the development seeds
  (Oakline Lawn & Landscape) with headless Chrome at 2x: staff screens at 1280×820 with the
  sidebar cropped, client and technician screens at 390×844. Retake them the same way from
  staging before launch, keeping the file names.
- About: why Shadetree exists and the six promises it keeps (from `docs/plans/00-vision.md`),
  with no stock photos. The founder's own story is still to come (open question), so its
  criterion stays open.

## Open questions

- The About page needs the founder's own story: who builds Shadetree and why (part 2 drafts
  the structure without inventing it).
