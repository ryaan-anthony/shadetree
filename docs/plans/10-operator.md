# 10 · Operator console

## Purpose

Give the people running Shadetree what they need to support businesses and run the company —
safely, with every sensitive action audited — and nothing more.

## Current state

Nothing implemented. The original "SaaS owner backend" plan had six epics including in-house
invoicing, financial reporting, a feature-toggle dashboard, and fine-grained support permission
management.

## Requirements

### Access
- **R1** Operators are a separate class of user from business members. Operator access is
  granted only by another operator (first one via a console command) and can be revoked.
- **R2** Operators must use two-factor authentication. Operator sessions are short-lived.
- **R3** The console is separate from the business app (own area and layout), not reachable by
  business members, and not indexed.

### Business directory
- **R4** List and search businesses by name, owner email, plan, status, and signup date.
- **R5** A business page shows: owner and members, plan and subscription status, current usage
  vs limits, key activity counts (clients, quotes sent, jobs, invoices paid), signup and last
  activity dates, payment-account connection status, and operator notes.

### Support
- **R6** Impersonation: an operator can view the app as a specific member of a business, after
  entering a reason. A persistent banner shows impersonation is active; it ends explicitly or on
  timeout.
- **R7** During impersonation, sensitive actions are blocked (changing passwords/emails, billing,
  connecting payment accounts, deleting the business). Read access is the default; write access
  requires an explicit "allow changes" choice that is also audited.
- **R8** Operators can add internal notes to a business.

### Account actions
- **R9** Suspend / reactivate a business (suspended businesses can't sign in; client links show
  a neutral "unavailable" page; payments in flight still settle).
- **R10** Comp a plan, extend a trial, apply a coupon (through the billing provider).
- **R11** Resend confirmation / reset password for a user. Delete a business and all its data
  (with confirmation and a waiting period), satisfying privacy erasure requests.
- **R12** Edit plans (09-billing), industry presets (03-catalog) and feature flags (PLT-11).

### Support tickets
- **R14** Members open support tickets from inside the app, with page and browser context
  attached automatically, and follow replies in the app or by email.
- **R15** Operators work from a single ticket inbox: assign, reply, add internal notes, set
  status. The business's context sits beside each ticket.
- **R16** Email replies and emails to the support address thread into tickets.

### Audit
- **R13** Every operator action (impersonation start/stop and reason, account actions, plan
  changes, flag changes) is recorded with who, when, what and target, and is viewable and
  filterable in the console. Audit records cannot be edited or deleted from the app.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | One operator role at launch; no permission matrix. | Team is 1–3 people. |
| D5 | Support tickets are between businesses and Shadetree; no knowledge base or live chat at launch. | One accountable support channel with context. |
| D2 | Financial reporting (MRR, churn) comes from the billing provider's dashboard at launch. | Duplicating it is wasted effort pre-scale. |
| D3 | Impersonation is read-only by default. | Limits blast radius of mistakes and abuse. |
| D4 | Console built in-app with the same UI foundation; no third-party admin framework unless an ADR argues for it. | Keeps one stack; operator needs are narrow. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [OPS-01](../specs/operator/OPS-01-operator-access.md) | Operator access & audit log | M5 | ACC-01, PLT-05 |
| [OPS-02](../specs/operator/OPS-02-business-directory.md) | Business directory | M5 | OPS-01, BIL-01 |
| [OPS-03](../specs/operator/OPS-03-impersonation.md) | Impersonation | M5 | OPS-02, ACC-04 |
| [OPS-04](../specs/operator/OPS-04-account-actions.md) | Account actions | M5 | OPS-02, BIL-05, PLT-11 |
| [OPS-05](../specs/operator/OPS-05-support-tickets.md) | Support tickets | M5 | OPS-02, NTF-02 |

## Backlog (M6)

- Platform metrics dashboard (signups, activation funnel, active businesses, MRR from provider).
- Admin UI for plans, presets and flags beyond simple forms.
- Multiple operator roles (support vs admin).
- Customer-facing status page.

## Open questions

1. Should businesses be told (email or in-app log) when an operator impersonated them?
   Recommend an entry in the business's activity log; required by some customers' expectations.
2. Waiting period before permanent deletion — recommend 30 days, operator can expedite for
   privacy requests.
3. Is a lightweight admin framework acceptable for the console to save time? Engineering
   decision; record in an ADR.
