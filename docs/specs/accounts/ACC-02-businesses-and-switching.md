---
id: ACC-02
title: Businesses & switching
domain: accounts
milestone: M1
depends_on: [ACC-01, PLT-06]
---
# ACC-02 · Businesses & switching

> Requirements: [02-accounts](../../plans/02-accounts.md) R5, R6, R7

## Summary

A user creates a business and becomes its Owner; a user may belong to several businesses and
switch between them safely. This already partially exists — refine it onto the tenancy
guardrails so that the "current business" is always explicit and correct.

## User stories

- As a new owner, I want to create my business with just a name and industry so that I can get
  to my first quote fast.
- As a consultant who works for two businesses, I want to switch between them and always know
  which one I'm in.

## Acceptance criteria

- [ ] After sign-up (or when a user has no active memberships), the user is taken to "create
      your business" requiring only name and industry; everything else is optional later.
- [ ] Creating a business makes the creator its Owner and sets it as current.
- [ ] Users with several active memberships can switch from the app chrome on desktop and
      mobile; the current business name (and logo, once set) is always visible.
- [ ] Switching is a normal, forgery-protected request; it can only select businesses where the
      user has an active membership; the selection persists across sessions.
- [ ] Removing a user's last membership in the current business moves them to another business
      or to "create your business".
- [ ] A business always has at least one Owner; the last Owner cannot leave or be demoted.
- [ ] Users can create additional businesses from the switcher (subject to plan rules later).
- [ ] Tests cover switching, membership loss, and cross-tenant denial.

## Out of scope

- Business profile fields beyond name and industry (CAT-01). Invitations (ACC-03).
- Ownership transfer UI (backlog; operators can do it).

## Open questions

- Should creating additional businesses be limited on the Free plan (e.g. one free business per
  user)? Owned by BIL-01.
