---
id: PLT-22
title: "Design system: logo upload and where the brand colour applies"
domain: platform
milestone: M6
depends_on: [PLT-05]
---
# PLT-22 · Design system: logo upload and where the brand colour applies

> Requirements: [01-platform](../../plans/01-platform.md) R28

## Summary

The admin audit (#314, item 12) found the logo upload in Settings → Branding is the browser's
own "Choose File / No file chosen" control. It also found the admin silently doesn't use the
business's brand colour. Give the upload a proper drop area, and say in Branding where the
colour applies. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want to drop my logo onto the page and see that it worked.
- As an owner, I want to know where my brand colour shows, so I'm not surprised that my admin
  is still green.

## Acceptance criteria

- [ ] Branding's logo field is a styled drop area: "Drop your logo here, or browse", with the
      accepted types and size limit (PNG, JPEG or WebP, up to 5 MB).
  - It shows the chosen file's name and preview before saving.
  - It shows the existing errors (wrong type, too large) as today.
- [ ] It works by keyboard and with a screen reader. Without JavaScript it falls back to a plain
      file field that still uploads.
- [ ] Branding's colour section says where the colour applies: "Your brand color shows on
      quotes, invoices, emails and client pages. Your admin stays Shadetree green." (US
      spelling, as in the rest of the app.)
- [ ] The admin's own colours don't change. The business's initials tile in the sidebar and the
      preview keeps its brand colour.
- [ ] Tests: an upload through the drop area and through the fallback field, the error cases,
      and an axe check of Branding with the drop area.
- [ ] Desktop (1280) and phone (390) screenshots of Branding, before and after choosing a file.

## Out of scope

- Using the business's colour in the admin.
- Other uploads (job photos, attachments, client imports), which keep their own controls.
- Logo cropping or editing.

## Decisions

- The admin is always Shadetree's green and navy, and the business's colour is client-facing
  only. Branding says so in one sentence (owner, 2026-11-22).
