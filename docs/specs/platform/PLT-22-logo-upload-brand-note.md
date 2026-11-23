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

- [x] Branding's logo field is a styled drop area: "Drop your logo here, or browse", with the
      accepted types and size limit (PNG, JPEG or WebP, up to 5 MB).
  - It shows the chosen file's name and preview before saving.
  - It shows the existing errors (wrong type, too large) as today.
- [x] It works by keyboard and with a screen reader. Without JavaScript it falls back to a plain
      file field that still uploads.
- [x] Branding's colour section says where the colour applies: "Your brand color shows on
      quotes, invoices, emails and client pages. Your admin stays Shadetree green." (US
      spelling, as in the rest of the app.)
- [x] The admin's own colours don't change. The business's initials tile in the sidebar and the
      preview keeps its brand colour.
- [x] Tests: an upload through the drop area and through the fallback field, the error cases,
      and an axe check of Branding with the drop area.
- [ ] Desktop (1280) and phone (390) screenshots of Branding, before and after choosing a file.

## Out of scope

- Using the business's colour in the admin.
- Other uploads (job photos, attachments, client imports), which keep their own controls.
- Logo cropping or editing.

## Decisions

- The admin is always Shadetree's green and navy, and the business's colour is client-facing
  only. Branding says so in one sentence (owner, 2026-11-22).

## Implementation notes

- The kit's file upload is `f.file_drop` (`components/_file_drop`, `file_drop_controller.js`,
  `.file-drop` classes, in the style guide). The page has a label, a plain file field and its
  limits; the controller makes the zone a drop area, hides the real input only visually
  (Tab, Enter/Space, the picker and screen readers stay the browser's), puts a dropped file
  into it, and shows its name, size and preview. Type and size are refused before saving in
  `LogoUpload`'s own words (`TYPE_ERROR`, `size_error`), read out once; the server's checks
  (#358) are unchanged. A file dropped beside the zone is ignored rather than opened.
- The input is named by its label only, and described by the limits, help and check lines;
  `f.field` and `f.file_drop` keep a caller's own `aria-describedby` (and labelledby, actions).
- `brand_preview` takes the chosen logo from `file-drop:chosen` instead of checking it itself.
- The colour sentence describes the presets, picker and hex field (`aria-describedby`).
- Dev seeds: none new. The demo business has no logo, so Branding shows the empty drop area.
