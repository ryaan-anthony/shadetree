---
id: CAT-05
title: Industry presets
domain: catalog
milestone: M1
depends_on: [CAT-03]
---
# CAT-05 · Industry presets

> Requirements: [03-catalog](../../plans/03-catalog.md) R13, R14

## Summary

"Industry-specific presets, not one-size-fits-all" is a core differentiator. When a business
picks its industry, offer a starter set of services and sensible defaults so the catalog isn't
empty and the first quote can be built immediately.

## User stories

- As a new house-cleaning business, I want common services (standard clean, deep clean,
  move-out clean) added for me so that I just fill in my prices.
- As the operator, I want to add or improve presets without a code deploy.

## Acceptance criteria

- [x] Industries are maintained as data, each with: display name, starter catalog items (name,
      description, unit, taxable, estimated duration; price optional), and default visit
      duration. (Preset content is database rows operators edit without a deploy; the list of
      industries and their display names stays in `config/industries.yml`, because business
      settings validate against it, so adding an industry is a deploy.)
- [x] Presets exist for the launch industry list (see open question) plus a generic "Other".
- [x] From the catalog page, an Owner/Admin can preview and add a preset's items in one action,
      choosing which to include. (Onboarding offers the same step: ACC-05.)
- [x] Adding a preset twice does not create duplicates (matching by name is acceptable).
- [x] Items added from presets are ordinary catalog items afterward (fully editable).
- [x] Industry data is seeded in every environment and can be updated by operators
      (a console/command is enough until the operator console exists).
- [x] Tests cover adding, de-duplication and tenancy.

## Out of scope

- Industry-specific request form questions (backlog). Industry marketing pages (backlog).

## Open questions

- ~~Which industries launch with presets, and who writes the starter items?~~ Resolved: every
  industry in `config/industries.yml` has a preset, including the recommended six (pressure
  washing was added as an industry) and "Something else". The first drafts are in
  `db/seeds/industry_presets.yml`; the operator owns the content from here.
- ~~Include suggested prices?~~ Resolved: no. Owners fill in their own prices.
