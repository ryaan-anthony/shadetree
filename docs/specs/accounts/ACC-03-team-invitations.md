---
id: ACC-03
title: Team invitations & membership
domain: accounts
milestone: M1
depends_on: [ACC-02]
---
# ACC-03 · Team invitations & membership

> Requirements: [02-accounts](../../plans/02-accounts.md) R8, R9

## Summary

Owners and Admins bring their team into Shadetree by email invitation, choosing a role up
front. They can see who has access, resend or revoke pending invites, and deactivate people who
leave — without losing the history of what those people did.

## User stories

- As an owner, I want to invite my technician by email so that they can see their visits on
  their phone.
- As an invitee, I want to accept with one click and set a password if I'm new.
- As an admin, I want to remove access immediately when someone leaves the company.

## Acceptance criteria

- [ ] Team page lists active members (name, email, role, last active), pending invitations, and
      deactivated members.
- [ ] Owners/Admins invite by email with a role (Admins cannot invite Owners). Inviting an
      existing member or pending email is prevented with a clear message.
- [ ] The invitation email names the business and inviter and links to accept; invitations
      expire (e.g. 7 days) and can be resent (new expiry) or revoked.
- [ ] Accepting while signed out lets a new user create an account (email pre-filled, confirmed
      by the act of accepting) or an existing user sign in; the membership is created and the
      business becomes current.
- [ ] Accepting with a different signed-in account than the invited email is handled clearly.
- [ ] Deactivating a member ends their access to that business immediately (including open
      sessions' next request); reactivating restores it with the same role.
- [ ] Deactivated members still appear by name on historic records.
- [ ] Role and tenancy rules are covered by tests.

## Out of scope

- What each role can do (ACC-04). Member limits per plan (BIL-01/03).

## Open questions

- ~~Should invitations also be shareable as a link?~~ Resolved: yes. "Copy link" on the team
  page, with the same expiry and revocation as the email.
