# 00 · Vision, scope and principles

## Mission

Help small service businesses run the money-making part of their day — **request → quote →
approval → schedule → work → invoice → paid** — from a phone, in minutes, for a price that is
free until the software is clearly earning its keep.

## The problem

Owners of 1–10 person service crews (cleaners, landscapers, handymen, pest control, HVAC,
detailers, mobile groomers …) still quote by text message, paper, or a Word template. Approvals
get lost, scheduling lives on a whiteboard, and invoices go out late. Existing field-service
suites solve this, but they are priced per seat, take hours to set up, and are built for
businesses that are already digital.

## Who we serve

| Persona | Description | What they need from us |
| --- | --- | --- |
| **Owner** | Runs the business, often also does the work. Non-technical, mobile-first. | Send a professional quote in under 3 minutes; know what needs attention today; get paid faster. |
| **Office admin** | Part-time help answering phones, building quotes, scheduling. | Fast data entry, a clear calendar, one list of what's outstanding. |
| **Technician** | Does the work in the field. | Today's visits, address, client contact, notes/photos, mark done; drafts quotes for requests given to them, for the office to check and send. Nothing else. |
| **Client** | The business's customer (homeowner, property manager). | Request, approve, pick a time and pay **without creating an account**. |
| **Operator** | Us — the people running Shadetree. | See every tenant's health, support them safely, bill them fairly. |

**Not in scope (for now):** franchises and multi-location enterprises, regulated industries that
need HIPAA or similar compliance (the original niche list included medical/dental offices —
removed), dispatch/route optimization, inventory, payroll.

## Product principles

1. **Ten-minute setup.** A new business can send a real quote within ten minutes of signing up.
   Every setup step is skippable and has sensible defaults from industry presets.
2. **Clients never need an account.** Every client interaction happens through a secure link.
3. **Mobile-first, server-rendered.** Pages must be fast on a mid-range phone on a cellular
   connection. Prefer server-rendered HTML with light progressive enhancement.
4. **Fewer features, finished.** We would rather do the core loop exceptionally than ship
   workflow builders, ticketing systems, and dashboards nobody asked for.
5. **Free tier that costs ~nothing to serve.** Anything with real marginal cost (SMS, large file
   storage, payment fees) is metered or paid-only.
6. **Honest pricing.** Price on value delivered (usage), not seats. No surprise lock-outs —
   limits never break a client-facing flow already in progress.
7. **Your data is yours.** A business can export everything at any time.
8. **White-label ready, not white-label first.** Client-facing pages carry the business's brand;
   reseller/agency white-labeling is a later concern.

## Glossary

| Term | Meaning |
| --- | --- |
| **Platform / Operator** | Shadetree itself and the people who run it. |
| **Business** | A tenant. Owns all of its data. A person can belong to several businesses. |
| **User** | A person who can sign in. |
| **Member** | A user's membership in a business, with a role: Owner, Admin or Technician. |
| **Client** | A business's customer. Has no login. Identified by contact details. |
| **Property** | A service address belonging to a client. A client may have several. |
| **Request** | An inbound ask for work, from the public request form or entered by staff. |
| **Service** | A catalog item the business sells (e.g. "Lawn mowing — per visit"). |
| **Quote** | A priced proposal sent to a client. Approved quotes become jobs. |
| **Job** | Work the business has agreed to do. Has one or more visits. |
| **Visit** | A scheduled block of time on a date, assigned to members. |
| **Invoice** | A request for payment, usually created from a job or quote. |
| **Payment** | Money received against an invoice, online or recorded manually. |
| **Plan** | The subscription tier a business is on, with limits and features. |
| **Client link** | A secure, expiring URL that lets a client view/act on one document. |

The word "customer" is deliberately avoided in code and UI because it was ambiguous in the
original plan (sometimes the business, sometimes the business's client).

## Domain map

| Domain | One-line purpose |
| --- | --- |
| [01 Platform](01-platform.md) | Stack, tenancy, CI/CD, security, conventions that every other domain relies on. |
| [02 Accounts](02-accounts.md) | Sign-up, sign-in, businesses, team members, roles, onboarding. |
| [03 Catalog](03-catalog.md) | Business profile, branding, services, taxes, presets, hours. |
| [04 Clients](04-clients.md) | Client records, properties, public request form, request inbox. |
| [05 Quotes](05-quotes.md) | Build, send, view, approve/decline, revise quotes. |
| [06 Jobs](06-jobs.md) | Jobs, visits, calendar, technician day view. |
| [07 Payments](07-payments.md) | Invoices, online payments, recorded payments, balances. |
| [08 Notifications](08-notifications.md) | Email to clients and team, message templates, workflow automations. |
| [09 Billing](09-billing.md) | Our plans, usage limits, subscriptions. |
| [10 Operator](10-operator.md) | Internal console: tenants, impersonation, account actions, support tickets. |
| [11 Marketing](11-marketing.md) | Public website, legal pages, lead capture. |
| [12 Insights](12-insights.md) | Action dashboard, data export, (later) reporting. |

## Milestones

Milestones are ordered; work inside a milestone is parallelizable unless a spec says otherwise.

| Milestone | Goal | Exit criteria |
| --- | --- | --- |
| **M0 Foundation** | The codebase is safe and pleasant for several developers/agents to work in at once. | CI green and required; stack decisions recorded; tenancy guardrails; UI shell; dependency backlog cleared. |
| **M1 Workspace** | A business can sign up, invite its team, describe itself and its services, and store clients. | A new owner can create a business, set up profile, branding, services and taxes, invite a team member and add clients. Staging deploys automatically. |
| **M2 Quote → Approval** | First real value: send a branded quote and get it approved online. | A new owner is guided from sign-up to a sent quote; a client receives it by email, views it on a phone, and approves it; the business is notified. Public request form feeds an inbox. |
| **M3 Schedule → Work** | Turn approved work into scheduled visits that technicians complete. | Approved quote → job → visit on calendar → technician completes it from a phone. |
| **M4 Invoice → Paid** | Close the loop with invoicing and online payment. **MVP / private beta.** | Completed job → invoice → client pays by card → business sees it paid. |
| **M5 Launch** | Everything needed to charge money and open sign-ups publicly, plus the paid-tier features. | Plans and limits enforced, subscriptions live, operator console with support tickets, legal pages, marketing site, exports; automations, custom roles and multi-location available on paid plans. |
| **M6 Growth** | Features that widen the funnel and deepen retention. | Specified after M4 based on beta feedback (see each domain's backlog). |

## What changed from the original plan

The original plan (in `.project/`) was written as a broad feature inventory. Reviewing it as a
new principal engineer, these are the decisions that were questioned and changed:

| Original | Now | Why |
| --- | --- | --- |
| Admin portal had no quote builder, jobs, or invoices; those only existed as "customer-facing" features. | Quotes, jobs and invoices are first-class domains with both a staff side and a client side. | The core loop was split across documents and the staff half was missing. |
| Workflow builder, approval chains, task automation. | Kept, but rebuilt as **automations** (trigger → delay → condition → action from fixed catalogs, with ready-made recipes) in M5, after the core loop exists. No visual flow builder. | A free-form builder contradicts "minimal setup"; recipes deliver the follow-up value with little setup. |
| Support ticketing, knowledge base, internal chat inside the admin portal. | Kept as **support tickets between businesses and Shadetree** (M5), with email threading, and a **knowledge base** that grows with the app (OPS-06, M6; owner, 2026-11-22, reversing "no knowledge base at launch"). Internal chat cut. A helpdesk for businesses' own clients is an open question. | One support channel with full context; the rest had no clear owner. |
| Dynamic/seasonal pricing, bundles, packages, upsells, price audit trail. | Cut to: services with a default price, optional per-quote overrides, discounts, taxes. | Quotes are hand-tuned anyway; complexity hurts setup time. |
| Multi-location with per-location prices, taxes, fees, hours. | Kept, but **added on top** of a single-location core in M5 (`CAT-07`, `CAT-08`) and invisible until a second location is added. Fees become ordinary services. | Most target businesses have one base; building the core single-location first keeps M1–M4 simple. |
| Custom roles with JSON permission sets, plus a separate staff/member model. | One membership concept. Three built-in roles at launch, built on a permission catalog, with **custom roles** in M5 (`ACC-07`). | Two overlapping models existed; built-in roles cover the MVP and custom roles come once the permission catalog is proven. |
| Notification trigger builder, broadcast messaging, delivery analytics. | Fixed transactional messages; editable copy later; SMS later and metered. | Marketing broadcasts carry legal/compliance risk and cost. |
| Digital signatures as a legal compliance framework with multiple capture methods. | Approval records name, typed signature, timestamp, IP and the exact quote version approved. | Sufficient evidence for service quotes; drawn signatures optional later. |
| Building our own SaaS invoicing, dunning and payment-method storage. | Use the payment provider's hosted subscription billing. | Billing is not our differentiator; PCI scope and dunning are solved problems. |
| Google/Outlook two-way calendar sync in MVP. | One-way calendar feed in Growth; two-way only if demanded. | Two-way sync is expensive to build and support. |
| Docs specified PostgreSQL, Redis, Sidekiq, RSpec, ViewComponent; app uses SQLite, Solid Queue/Cache/Cable, Minitest, Tailwind via CDN. | Stack decisions re-made explicitly and recorded (`PLT-01`). | Plan and code disagreed; neither was recorded as a decision. |
| Detailed implementation notes (file paths, columns) inside requirements. | Specs describe outcomes only. | Implementation belongs to the developer; stale notes mislead agents. |
| End clients modeled as users (`customer_id → users`). | Clients are tenant data, not users. | Clients never sign in; mixing them with users leaks across tenants. |
| Account tier stored on the user. | Plan belongs to the business. | A user can belong to several businesses on different plans. |

## Cross-cutting requirements

These apply to every spec; acceptance criteria assume them without repeating them.

- **Tenancy:** A member can only ever see and change data of businesses they belong to. Every
  feature includes a test proving cross-tenant access is denied.
- **Roles:** Owner > Admin > Technician. Technicians see only what is assigned to them plus the
  client details needed to do the work, and draft quotes for their requests for review (QTE-07). Each spec states any role rules that differ.
- **Performance:** Primary pages render server-side in under 300 ms (p95) at launch scale;
  client-facing pages are usable on a 3G connection and score ≥ 90 on mobile Lighthouse.
- **Accessibility:** WCAG 2.1 AA for client-facing pages; keyboard and screen-reader usable
  staff pages.
- **Mobile:** Every staff and client page works at 360 px wide.
- **Time & money:** All times shown in the business's time zone; money stored exactly, displayed
  in the business's currency.
- **Privacy:** Collect only what is needed; client personal data is exportable and deletable;
  no client data in logs or third-party analytics.
- **Reliability:** Client-facing links and payment pages are the highest-availability surface.
- **Observability:** Errors are reported with tenant context but no personal data.
- **Testing:** Each spec's acceptance criteria are covered by automated tests that run in CI.
- **Copy:** Plain language, no jargon; all user-facing strings are localizable (English only at
  launch).

## Business model (working assumptions)

- **Free plan** forever, limited by usage (e.g. a small number of quotes sent per month), with
  full core loop.
- **Paid plans** unlock higher usage and premium features (custom branding removal, more
  team members, message templates, automations, custom roles, multiple locations, later SMS). Price range roughly $15–$99/month.
- **Usage, not seats.** Team size is not the primary price lever.
- **Optional platform fee** on online client payments is a possible revenue line (open question).
- Exact limits and prices are owned by `09-billing` and are configurable without a deploy.

## Global open questions

| # | Question | Recommendation | Owner spec |
| --- | --- | --- | --- |
| G1 | ~~Primary database?~~ **Decided: PostgreSQL** ([ADR 0002](../adr/0002-postgresql.md)). | Switch happens in PLT-07. | PLT-01 |
| G2 | Which payment provider for client payments and our subscriptions? | Stripe (Connect for client payments, Billing for subscriptions). | PAY-03, BIL-04 |
| G3 | What is the billable usage metric? | Quotes sent per month (simple, understood, maps to value). | BIL-01 |
| G4 | ~~Production data to preserve?~~ **Decided: none.** | Schema reset and squashed migrations in PLT-07. | PLT-07 |
| G5 | Is the marketing site staying inside the Rails app? | Yes until launch; revisit if marketing needs a CMS. | MKT-01 |
| G6 | Do we keep `.project/` in the repo? | Keep until M1 completes, then delete (history is in git). | — |
| G7 | Primary market and currency at launch? | US/USD first, data model allows other currencies. | PLT-08 |
| G8 | ~~Brand and domain?~~ **Decided: `getshadetree.com`**, which email also sends from ([ADR 0017](../adr/0017-transactional-email-smtp.md)). | — | MKT-01, NTF-01 |

## Definition of done (for any spec)

- All acceptance criteria are met and covered by automated tests.
- Cross-cutting requirements above hold (tenancy test present, mobile layout checked).
- CI is green; no new security scanner warnings.
- User-facing copy reviewed; empty states and error states designed.
- Any significant technical decision is recorded as an ADR.
- The spec's open questions are resolved or explicitly deferred, and the spec is updated.
