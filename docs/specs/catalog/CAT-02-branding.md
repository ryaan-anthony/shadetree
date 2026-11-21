---
id: CAT-02
title: Branding
domain: catalog
milestone: M1
depends_on: [CAT-01]
---
# CAT-02 · Branding

> Requirements: [03-catalog](../../plans/03-catalog.md) R4, R5, R6

## Summary

Client-facing pages, PDFs and emails should look like the business, not like Shadetree. Let an
owner upload a logo and pick a brand color with a live preview, and give every client-facing
surface one consistent way to apply that branding.

## User stories

- As an owner, I want my logo and color on quotes so that I look professional next to bigger
  competitors.
- As an owner without a logo, I want something that still looks good using just my business name.

## Acceptance criteria

- [x] Owners/Admins can upload, replace and remove a logo (allowed image types, size limit,
      automatically resized for web, email and PDF use).
- [x] Owners/Admins pick a brand color from presets or a custom value; the app derives a
      readable text color and warns if contrast is insufficient.
- [x] A live preview shows a sample client-facing page header and primary button as settings
      change.
- [x] Without a logo, a tasteful name-based wordmark is used.
- [x] A single branding source is consumed by the client layout (PLT-05), and is ready for PDFs
      (QTE-02) and emails (NTF-01).
- [x] A "Powered by Shadetree" mark appears on client-facing pages; its visibility is controlled
      by an entitlement (wired to plans in BIL-01; visible to all until then).
- [x] The existing branding tab and logo-URL field are replaced by the upload.
- [x] Tests cover upload validation, contrast fallback and role access.

## Decisions

- **Readable text on any brand color** (owner, 2026-11-21, QA #274): the business's color is
  used as chosen for accents. Link text uses it darkened (same hue, 1% steps toward black) to
  4.5:1 on the client page (`Branding#link_color`, `--color-brand-link`); a button whose text
  can't reach 4.5:1 in white or ink gets a darkened background with white text
  (`#button_color`, `--color-brand-button`; hover only raises contrast). Colors that pass are unchanged; the settings note
  says what happens. Emails get the same values inline, and the preview computes them live.

## Out of scope

- Custom fonts, custom CSS, custom domains (backlog). Email sender domain (NTF backlog).

## Open questions

- ~~Storage location for uploads depends on the PLT-01 file-storage ADR.~~ Resolved: Active
  Storage per ADR 0008 (local disk in development and test; the S3-compatible bucket is
  configured with the environments in PLT-09).
- ~~Should we offer a few accent presets per industry?~~ Resolved: one set of eight presets
  that all pass the contrast checks; per-industry accents are backlog.
