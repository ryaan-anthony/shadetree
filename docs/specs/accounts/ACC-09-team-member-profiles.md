---
id: ACC-09
title: Team member profiles
domain: accounts
milestone: M6
depends_on: [ACC-06, ACC-07, JOB-03, JOB-04, OPS-03, INS-02]
---
# ACC-09 · Team member profiles

> Requirements: [02-accounts](../../plans/02-accounts.md) R16

## Summary

Each team member gets a small profile: a photo, a title or short bio and a work phone. Staff see
faces next to names on the Team page, the schedule and My day. When the business turns it on,
clients see a member's photo, first name, title or bio and a phone number in what's sent to them
about a visit (JOB-12 "On my way" first), so they know who is coming to their door.

## User stories

- As a technician, I want to add my photo from my phone so the client recognises me at the door.
- As an office manager, I want to add photos for crew members who won't do it themselves.
- As an owner, I want to decide whether clients see my team at all, and never hand out anyone's
  personal number by accident.

## Acceptance criteria

- [ ] Each member has a profile in each business they belong to: a photo, a title (up to 40
      characters, e.g. "Lead technician"), a short bio (up to 200 characters, plain text) and a
      work phone, all optional. The first name is the account's own (ACC-06), not a new field.
- [ ] A member edits their own profile from the user menu ("Your profile in <business>"), in any
      role. People with `manage_team` edit others' from the Team page; only those with
      `manage_owners` edit an Owner's (ACC-07's rule). Anyone else is refused, with role and
      cross-tenant tests.
- [ ] Photos reuse the existing photo cleaning: PNG, JPEG or WebP, up to 10 MB and 8,000 px a
      side, at least 128 px; re-encoded with all metadata (EXIF, GPS) removed, and upright (the
      shared orientation fix; see Decisions). Shown as a centred square (round on screen), no
      crop tool; Replace and Remove work, and so does a phone camera at 360 px.
- [ ] Without a photo, initials show (the kit's avatar); clients see the first initial only.
- [ ] Staff see photos and titles on the Team page, on visit assignees in the schedule and on
      job pages, and on My day (the person and their crew-mates on each visit). Lists stay fast.
- [ ] A business setting, "Show team profiles to clients", is off by default. Off, clients see
      no team names, photos, bios or phones anywhere (as today). On, client-facing visit messages
      and pages may show a member's photo, first name, title, bio and phone, and nothing else (no
      last name, email or account details).
- [ ] The phone clients see is the member's work phone if set, otherwise the business's (the
      job's location's, CAT-07); if neither, none. The field says "Clients see this number".
- [ ] Clients load a photo only through the visit's client link, while the setting is on and the
      member is active: turning the setting off or deactivating the member stops it at once.
      There's no lasting public link to a photo.
- [ ] Deactivated members are hidden from clients and keep their profile for staff and history.
      Deleting an account (ACC-06) removes its photo, title, bio and work phone in every
      business ("Former member", no photo). Emails already sent can't be recalled; the deletion
      page says so.
- [ ] Changes made by someone else are recorded (who, what, when) and the member gets an in-app
      notice. Support viewing as a member (OPS-03) sees profiles but can't change them in either
      mode.
- [ ] The full data export (INS-02) stays without team data; its README says profiles aren't in it.
- [ ] Where the name sits next to the photo, the image is decorative; elsewhere its alt text is
      the name that viewer may see ("Marcus" for clients, "Marcus Reed" for staff). The upload is
      labelled, errors are announced, and axe passes on the profile page, Team and My day.
- [ ] Tests cover editing rights, metadata removal (a photo with GPS comes out without it),
      size limits, the client setting, deactivation, deletion, impersonation and
      tenancy. Dev seeds give Marcus a photo and title; one crew member has none.

## Out of scope

- Naming the crew in booking confirmations, reminders or the visit page (backlog; Decisions).
- A public "Meet the team" page, ratings or reviews of members, per-member opt-out (owner).

## Decisions

- Clients may see a member's photo, first name only, a short bio or title, and a phone number
  (owner, 2026-11-22).
- Showing profiles to clients is a business-level setting, with no per-member opt-out
  (owner, 2026-11-22).
- **Phone privacy:** an optional work phone on the profile, falling back to the business's (the
  job's location's), so a tech's personal number is never shown by default; neither set, no
  phone (owner, 2026-11-22).
- Bios need no office approval: `manage_team` can edit or clear any bio, changes are recorded
  and the member is told (owner, 2026-11-22).
- Without a photo, initials show; clients see the first initial only (owner, 2026-11-22).
- One profile per business, not per person (owner, 2026-11-22).
- Title (40 characters) and bio (200) are two fields: "Marcus · Lead technician"
  (owner, 2026-11-22).
- "Show team profiles to clients" lives on the Team page, for `business_settings`, linked from
  Settings → Messages (owner, 2026-11-22).
- Naming the crew on confirmations, reminders and the visit page is backlog: crews change after
  booking (owner, 2026-11-22).
- Photos coming out sideways (the shared cleaning dropped the orientation tag without turning
  the image) is fixed in its own PR, as it affects visit and request photos on main today;
  ACC-09 relies on that fix rather than carrying it (owner, 2026-11-22).

## Open questions

- None.
