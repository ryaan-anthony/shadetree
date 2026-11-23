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

Each team member gets a small profile: a photo, a title, a short bio and a work phone. Staff see
faces next to names on the Team page, the schedule and My day. When the business turns it on,
clients see a member's photo, first name, title and a phone number in what's sent to them about
a visit (JOB-12 "On my way" first), so they know who is coming to their door.

## User stories

- As a technician, I want to add my photo from my phone so the client recognises me at the door.
- As an office manager, I want to add photos for crew members who won't do it themselves.
- As an owner, I want to decide whether clients see my team, and never hand out anyone's
  personal number by accident.

## Acceptance criteria

- [x] Each member has a profile in each business they belong to: photo, title (up to 40
      characters, e.g. "Lead technician"), short bio (up to 200, plain text) and work phone, all
      optional. The first name is the account's (ACC-06). With no first name, clients see no name
      (never the full name or email, which staff pages fall back to), tested.
- [x] A member edits their own profile from the user menu ("Your profile in <business>"), in any
      role. People with `manage_team` edit others' from the Team page (Technicians can't open it);
      only `manage_owners` edits an Owner's (ACC-07's rule). Others are refused; role and
      cross-tenant tests.
- [x] Photos use the shared photo cleaning, which turns them upright (#358, a prerequisite) and
      removes all metadata (EXIF, GPS): PNG, JPEG or WebP, up to 10 MB (visit photos allow 20)
      and 8,000 px a side, at least 128 px (the cleaning's minimum is 1 px today, so it gains an
      option). Shown as a centred square (round on screen), no crop tool; Replace and Remove
      work, and so does a phone camera at 360 px.
- [x] Without a photo, initials show (the kit's avatar); clients see the first initial only.
- [x] Staff see photos and titles on the Team page, on visit assignees in the schedule and on
      job pages, and on My day (the person and their crew-mates on each visit). Lists stay fast.
- [x] "Show team profiles to clients" in Settings → Messages (`business_settings`), linked from
      the Team page, is off by default. Off, clients see no team names, photos or phones (as
      today). On, client visit messages and pages may show a member's photo, first name, title
      and phone, and nothing else (no last name, email or account details).
- [x] The phone clients see is the member's work phone if set, otherwise the business's (the
      job's location's, CAT-07); if neither, none. The field says "Clients see this number".
- [x] Clients load a photo only under the visit's client link (/c/:token/…), checked on every
      request as quote and invoice files are, then redirected to a storage URL that expires in 5
      minutes. Only a member assigned to that visit, while the setting is on, the member is active
      and a card or message shows them. A test shows another member's photo can't be fetched.
- [x] Deactivated members are hidden from clients and keep their profile for staff and history.
      Deleting an account (ACC-06) explicitly removes the photo (file and sizes) and clears
      title, bio and work phone in every business, as deletion skips callbacks; deleting a
      business (OPS-04) removes its profile photos too. Emails already sent can't be recalled;
      the account deletion page says so.
- [x] Changes by someone else are recorded (who, what, when) in a history on the member's Team
      row, and the member gets an in-app notice. Support viewing as a member (OPS-03) sees
      profiles but can't change them in either mode.
- [x] The full data export (INS-02) stays without team data; its README says profiles aren't in it.
- [x] Where the name sits next to the photo, the image is decorative; elsewhere its alt text is
      the name that viewer may see ("Marcus" for clients, "Marcus Reed" for staff). The upload is
      labelled, errors are announced, and axe passes on the profile page, Team and My day.
- [x] Tests cover editing rights, metadata removal, size limits, the client setting, photo
      access, deactivation, deletion, impersonation and tenancy. Dev seeds give Marcus a photo
      and title; one crew member has none.

## Out of scope

- Naming the crew in booking confirmations, reminders or the visit page (backlog; Decisions).
- A public "Meet the team" page, ratings or reviews, per-member opt-out (owner).

## Implementation notes

- Clients get `Visit#client_team_shown` (nobody without a first name), empty until JOB-12 fills
  `Visit#client_team_card_user_ids`. History keeps field names only. Seeds: Marcus, Priya, Dana.

## Decisions

- Clients may see a member's photo, first name only, a short bio or title, and a phone number;
  a business-level setting, no per-member opt-out (owner, 2026-11-22).
- **Phone privacy:** an optional work phone, falling back to the business's, so a tech's
  personal number is never shown by default; neither set, no phone (owner, 2026-11-22).
- Bios need no office approval: `manage_team` can edit or clear any bio, changes are recorded
  and the member is told (owner, 2026-11-22).
- Initials without a photo; one profile per business; title (40) and bio (200) as two fields
  (owner, 2026-11-22).
- "Show team profiles to clients" lives in Settings → Messages, linked from Team
  (owner, 2026-11-22).
- The client card shows photo, first name and title only; the bio stays on the member's profile
  (owner, 2026-11-22).
- Naming the crew on confirmations, reminders and the visit page is backlog (owner, 2026-11-22).
- Upright photos come from #358, which fixes the shared cleaning for visit and request photos
  too; ACC-09 relies on it rather than carrying it (owner, 2026-11-22).

## Open questions

- None.
