# 03 · Business setup & catalog

## Purpose

Capture what a business is and what it sells, so that quotes and invoices can be built in a
few taps and client-facing pages look like the business, not like Shadetree.

## Current state

- Business record with name, industry (11 hard-coded values), address (free text), contact info,
  timezone, currency, brand color, logo URL, description, onboarding step.
- Hours and branding tabs exist in a setup UI.
- Tables exist (unused) for locations, operating hours per location, closures, special
  availability, service areas with restrictions, categories (nested), services, and per-location
  prices, taxes and fees.

## Requirements

### Profile
- **R1** A business has: name, industry, contact email, phone, website, structured postal
  address, time zone, currency, and a short description.
- **R2** Time zone defaults from the browser at creation; currency defaults from country.
- **R3** Business details appear on client-facing documents (quote, invoice) and emails.

### Branding
- **R4** Upload a logo (validated type and size) and pick a brand color with a live preview of a
  client-facing page. Contrast is checked so buttons remain readable.
- **R5** Branding is applied consistently to client pages, PDFs and emails.
- **R6** "Powered by Shadetree" appears on client-facing pages on the Free plan; removable on
  paid plans (feature gate defined in 09-billing).

### Services
- **R7** A service has: name, description (shown to clients), unit (e.g. each, hour, sq ft,
  visit), default unit price, whether it's taxable, optional estimated duration, and an
  active/archived state. Optional single-level category for grouping.
- **R8** Services can be reordered, archived (hidden from pickers, preserved on old documents),
  and duplicated.
- **R9** Prices on quotes/invoices are copied at the time they're added; changing a catalog
  price never changes an existing document.

### Taxes and fees
- **R10** A business defines one or more named tax rates and a default. Line items can be marked
  taxable or not; documents show tax per rate.
- **R11** Common fees (trip fee, disposal fee) are simply services; no separate fee system.
- **R12** Discounts are applied on documents (fixed or percent, per line or whole document),
  not configured in the catalog.

### Industry presets
- **R13** Each supported industry has a preset of starter services (names, units, suggested
  prices left blank or as placeholders) and default visit duration. Choosing an industry during
  onboarding offers to add them.
- **R14** Presets are data maintained by operators, not code changes.

### Hours & closures
- **R15** Weekly business hours (per weekday open/close or closed) and one-off closures (date
  ranges with a reason). Used by scheduling and later client self-booking.

### Locations (paid plans)
- **R16** A business can add locations, each with its own address, contact details, time zone,
  hours, closures and assigned members. Documents and visits belong to a location. A
  single-location business never sees location settings.
- **R17** Client-facing documents show the location's contact details. Lists, the calendar and
  the dashboard can be filtered by location.
- **R18** Catalog prices and default tax rates can be overridden per location.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Single-location core through M4. Multi-location (locations, per-location hours, prices and tax defaults) added in M5. Service areas and per-location fees are dropped. | Most target businesses have one base. Adding locations on top keeps M1–M4 simple while supporting growing businesses. |
| D2 | Fees are services. | One concept instead of two; users already think of trip fees as line items. |
| D3 | Discounts live on documents, not in the catalog. | Promotions/discount-code engines were speculative. |
| D4 | Single-level categories, optional. | Nested categories add UI complexity for no clear benefit. |
| D5 | Industry list is data, not a hard-coded enum. | Presets and marketing pages need to add industries without deploys. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [CAT-01](../specs/catalog/CAT-01-business-profile.md) | Business profile | M1 | ACC-02, PLT-08 |
| [CAT-02](../specs/catalog/CAT-02-branding.md) | Branding | M1 | CAT-01 |
| [CAT-03](../specs/catalog/CAT-03-service-catalog.md) | Service catalog | M1 | ACC-04, PLT-08 |
| [CAT-04](../specs/catalog/CAT-04-tax-rates.md) | Tax rates | M1 | CAT-03 |
| [CAT-05](../specs/catalog/CAT-05-industry-presets.md) | Industry presets | M1 | CAT-03 |
| [CAT-06](../specs/catalog/CAT-06-hours-closures.md) | Business hours & closures | M3 | CAT-01 |
| [CAT-07](../specs/catalog/CAT-07-locations.md) | Locations | M5 | CAT-06, JOB-03, BIL-01 |
| [CAT-08](../specs/catalog/CAT-08-location-pricing.md) | Location pricing & taxes | M5 | CAT-07, CAT-04, QTE-01 |

## Backlog (M6)

- Service areas (zip/radius) to filter public requests.
- Optional service add-ons / options shown on quotes.
- Price lists (e.g. commercial vs residential).
- Separate payment accounts per location; location-scoped permissions.

## Open questions

1. Which industries ship with presets at launch? Recommend 6: cleaning, lawn/landscaping,
   handyman, pest control, painting, pressure washing / exterior cleaning.
2. Do presets include suggested prices? Recommend no — regional variance makes them misleading.
3. Tax complexity: is a flat list of named rates enough for US sales tax at launch? Recommend
   yes; automated tax calculation is out of scope.
4. Logo storage location depends on PLT-01 file-storage decision.
