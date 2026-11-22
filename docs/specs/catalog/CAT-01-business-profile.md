---
id: CAT-01
title: Business profile
domain: catalog
milestone: M1
depends_on: [ACC-02, PLT-08]
---
# CAT-01 · Business profile

> Requirements: [03-catalog](../../plans/03-catalog.md) R1, R2, R3

## Summary

Capture the business details that appear on every quote, invoice and client email, and the
settings (time zone, currency, document defaults) that other features rely on. Replaces the
current multi-tab setup screen with one clear settings area.

## User stories

- As an owner, I want my business name, contact details and address on every document so that
  clients know who they're dealing with.
- As an owner, I want to set my time zone and currency once so that everything else is right.
- As an admin, I want to set default quote terms and expiry so that I don't type them each time.

## Acceptance criteria

- [ ] Settings → Business lets Owners/Admins edit: name, industry, description, email, phone,
      website, structured address (street, unit, city, region, postal code, country), time zone
      and currency.
- [ ] Time zone defaults from the browser at creation; currency defaults from country; both
      validated against supported lists.
- [ ] Document defaults: quote expiry (days), default quote terms, default invoice payment terms
      and invoice terms, and document number prefixes. (Consumers: QTE-01, PAY-01.)
- [ ] Changes take effect for new documents only; existing documents keep the details they were
      created with.
- [ ] Industry options come from data (shared with CAT-05), not a hard-coded list.
- [ ] Technicians cannot access business settings.
- [ ] Validation errors are clear; the page works on mobile.
- [ ] Tests cover validation, role access and cross-tenant denial.

## Out of scope

- Logo and colors (CAT-02). Hours (CAT-06). Multi-location (backlog).

## Open questions

- ~~Snapshot or current details?~~ Resolved: documents copy `Business#document_snapshot`, and a
  sent document never changes (QTE-01 and INV-01 store it).
- ~~Is "country" needed at launch?~~ Resolved: yes, with ten supported countries, each setting
  the default currency and address wording.

## Decisions

- #289, 2026-11-22: Settings has one entry point (/admin/settings) and four groups: Business
  (details, hours, locations, branding, request form), Money (quotes, jobs & invoices, taxes, online
  payments), Messages (emails to clients, automations) and Plan and data. Pages keep their URLs
  (no renames; old links keep working); the groups live in one place, SettingsHelper.
