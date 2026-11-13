# 11 · Marketing site

## Purpose

Explain what Shadetree does in one screen, convince a skeptical, non-technical owner that it's
worth five minutes, and get them to "Start free". Also host the legal and trust pages a paid
product needs.

## Current state

Rails-rendered home, pricing, about and contact pages with a marketing layout; contact form
posts but there is no stored lead or notification; Tailwind via CDN. The original plan included
testimonials, blog, newsletter, demo booking, industry pages, and a knowledge base.

## Requirements

### Pages
- **R1** Home: one clear value proposition ("Quote it, book it, get paid"), the core loop
  illustrated, who it's for, pricing teaser, social proof (when real), and a single primary call
  to action: start free.
- **R2** Features: the core loop in more depth with real product screenshots.
- **R3** Pricing: plans and limits rendered from the same plan data as billing (09-billing), an
  FAQ, and clear free-plan messaging. No pricing hard-coded in templates.
- **R4** About: the "built by a small team for small businesses" story with real humans.
- **R5** Contact: form that stores the message, notifies the team, and confirms to the sender;
  spam-protected.
- **R6** Legal: Terms of Service, Privacy Policy, Acceptable Use, a data processing summary, and
  a cookie notice if any non-essential cookies are used. Linked from footer and sign-up.

### Quality
- **R7** Pages load fast and score ≥ 90 on mobile Lighthouse for performance, accessibility,
  best practices and SEO.
- **R8** Each page has title, description, canonical URL and social share metadata; a sitemap and
  robots file exist; the staff app and client links are excluded from indexing.
- **R9** Privacy-respecting analytics (no cross-site tracking cookies) measure visits → sign-ups.
- **R10** Copy is reviewed for plain language; claims are true (no invented metrics or fake
  testimonials).

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Keep marketing pages in the Rails app until launch. | Already built; one deploy; pricing can read plan data directly. |
| D2 | No blog, newsletter, demo booking or testimonials at launch. | Content needs an owner; testimonials need real customers. |
| D3 | Single CTA: start free. | Free plan removes the need for "book a demo" sales motion. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [MKT-01](../specs/marketing/MKT-01-site-refresh.md) | Marketing site refresh | M5 | PLT-05, BIL-01 |
| [MKT-02](../specs/marketing/MKT-02-contact-leads.md) | Contact form & leads | M5 | NTF-01, PLT-13 |
| [MKT-03](../specs/marketing/MKT-03-legal-pages.md) | Legal & trust pages | M5 | PLT-05 |
| [MKT-04](../specs/marketing/MKT-04-seo-analytics.md) | SEO, performance & analytics | M5 | MKT-01 |

## Backlog (M6)

- Industry landing pages ("Quoting software for lawn care") driven by industry data.
- Blog / changelog.
- Help center with how-to articles.
- Comparison pages vs incumbents.
- Referral and affiliate landing pages.

## Open questions

1. **Brand & domain (G8):** confirm name and primary domain before MKT-01 and NTF-01.
2. Who drafts the legal pages? Recommend a reputable template service reviewed by a lawyer before
   accepting payments. **(blocking for public launch)**
3. Analytics tool choice — engineering/product decision; must not require a cookie banner.
4. Should the marketing site move to a static site generator later for CMS-style editing?
