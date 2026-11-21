---
id: NTF-02
title: Team notifications
domain: notifications
milestone: M3
depends_on: [NTF-01, ACC-04]
---
# NTF-02 · Team notifications

> Requirements: [08-notifications](../../plans/08-notifications.md) R7, R8, R9

## Summary

Team members should hear about things that need them — a new request, an approved quote, a
visit assigned to them, a payment — in the app and, if they want, by email, without drowning in
noise.

## User stories

- As an owner, I want to know the moment a client approves a quote so that I can schedule it.
- As a technician, I want to know when I'm assigned a visit or my visit changes.
- As an admin, I want to turn off emails I don't need while still seeing them in the app.

## Acceptance criteria

- [x] An in-app notification center shows recent notifications with unread count in the app
      chrome (desktop and mobile); items link to the record and can be marked read
      individually or all at once. *A bell in the top bar; opening an item marks it read.*
- [ ] Notification types (initial set): new request; quote first viewed; quote approved,
      declined, changes requested; visit assigned/changed/cancelled (to assignees); job ready to
      invoice; invoice paid; online payment failed; team invitation accepted.
      *Done for the events that exist: new request, quote first viewed, approved, declined,
      changes requested, invitation accepted. Visits (JOB-02) and ready to invoice (JOB-04)
      are added; payments (PAY-*) add theirs when they're built. "Client email not delivered"
      (QA #274): a client email refused or not sent, emailed by default (not test emails or
      failures on Shadetree's side, which go to operators).*
- [x] Recipients are role-aware: Owners/Admins get business events; Technicians only get events
      about their own visits. *By permission; `to:` names the people for visit events (JOB-02).*
- [x] Each member can turn email on/off per type (in-app always on) in personal settings;
      defaults are sensible per role. *Notifications → Email settings, per business.*
- [x] Features raise notifications through one shared mechanism; adding a new type is a small,
      documented change. *`NotificationType.deliver`; CONTRIBUTING.md "Team notifications".*
- [x] Notifications respect tenancy (a member of two businesses sees each business's
      notifications in that business).
- [x] Old notifications are pruned after a retention period. *90 days, daily.*
- [x] Tests cover recipient rules, preferences and tenancy.

## Out of scope

- Push notifications, SMS to team, digests (backlog).

## Open questions

- ~~Should Owners get a daily digest email instead of individual emails?~~ *Decided: backlog.*
