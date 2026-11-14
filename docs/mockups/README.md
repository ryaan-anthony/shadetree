# Mockups

Clickable HTML mockups for milestones M1–M5, built from the specs in [`../specs`](../specs).
Open [`index.html`](index.html) in a browser (no build step, no network needed).

They replace the mockups in `.project/mockups`, which are superseded. The look keeps the
original navy and green brand (from `shadetree-enterprise.html`) but tightens it: one action
color, hairline borders instead of shadows, dense lists, tabular money, and real product
states in place of marketing illustrations.

## What these are, and what they are not

- **Are:** the reference for layout, content, copy tone, states (empty, error, warning,
  success) and flows for each spec. Each page names its specs in an HTML comment at the top.
- **Are not:** production code. Implementation choices (CSS approach, components, frameworks)
  belong to the developer of each spec, per PLT-01 and PLT-05. Copy the decisions, not the
  markup.
- Prices, limits and the sample business (Oakline Lawn & Landscape) are placeholders.

## Screens → specs

| Screen | File | Specs |
| --- | --- | --- |
| Marketing home | `marketing/home.html` | MKT-01, MKT-04 |
| Pricing | `marketing/pricing.html` | MKT-01, BIL-01 |
| Sign up / sign in | `marketing/sign-up.html`, `marketing/sign-in.html` | ACC-01, MKT-03 |
| Guided setup | `app/welcome.html` | ACC-02, ACC-05, CAT-05 |
| Home (action dashboard) | `app/dashboard.html` | INS-01, BIL-02, NTF-02 |
| Requests inbox | `app/requests.html` | CLI-04 |
| Quote builder + send | `app/quote-builder.html` | QTE-01, QTE-04, CAT-03, CAT-04 |
| Approved quote | `app/quote.html` | QTE-05, QTE-06 |
| Quotes list | `app/quotes.html` | QTE-06 |
| Schedule (week) | `app/schedule.html` | JOB-03, CAT-06 |
| Job + schedule visit | `app/job.html` | JOB-01, JOB-02, JOB-05 |
| Jobs list | `app/jobs.html` | JOB-01 |
| Invoice + record payment | `app/invoice.html` | PAY-01, PAY-02, PAY-05 |
| Invoices list | `app/invoices.html` | PAY-01 |
| Clients + import | `app/clients.html` | CLI-02, CLI-06 |
| Client | `app/client.html` | CLI-01, CLI-05, INS-02 |
| Business profile & branding | `app/settings.html` | CAT-01, CAT-02 |
| Services & pricing | `app/services.html` | CAT-03, CAT-05 |
| Team & roles | `app/team.html` | ACC-03, ACC-04, ACC-07 |
| Automations | `app/automations.html` | NTF-04 |
| Plan & billing | `app/plan.html` | BIL-01, BIL-03, BIL-04, BIL-05 |
| Technician day + visit | `tech/my-day.html` | JOB-04 |
| Client quote + approve | `client/quote.html` | PLT-12, QTE-03, QTE-05 |
| Client invoice + pay | `client/invoice.html` | PAY-02, PAY-04 |
| Public request form | `client/request.html` | CLI-03 |
| Quote email | `email/quote-sent.html` | NTF-01, QTE-04 |
| Operator console | `operator/console.html` | OPS-01 – OPS-05 |
| Viewing as a member | `app/dashboard.html#impersonate` | OPS-03 |
| Design system | `design-system.html` | PLT-05 |

Shared across staff pages (in `assets/app.js`): sidebar with business switcher (ACC-02),
⌘K search, "New" menu, notifications (NTF-02), new-client drawer with duplicate suggestion
(CLI-01) and the support request dialog (OPS-05).

## UX decisions worth carrying into the build

- **Home is a to-do list, not a chart wall.** Groups mirror the core loop and sort oldest
  first, so the dashboard tells the owner what to do next.
- **The progress rail** (Requested → Quoted → Approved → Scheduled → Done → Invoiced → Paid)
  appears on documents, client pages and the marketing hero. It is the product's visual
  signature, and it shows exactly where each piece of work stands.
- **Quote building stays on one page.** The catalog picker is inline, totals update live, and
  mobile gets a sticky total + Send bar. The send dialog shows the usage cost ("uses 1 of 109").
- **Client pages use the business's brand** (rust in the samples). Shadetree shows up only as a
  small "Sent with Shadetree" mark, which paid plans can hide.
- **Approval is a bottom sheet** with a typed signature and one checkbox, plus a clear success
  state and next steps.
- **Warnings don't block.** Scheduling overlaps and off-hours are warnings, never blockers
  (JOB-02 D3).
- **Settings live in one place.** The sidebar stays focused on daily work; everything you
  configure is under Settings, with its own section nav.
- **Copy is plain and consistent.** Sentence case, verbs on buttons, and the button's word
  repeats in the confirmation toast.

## Gaps / not mocked yet

Locations (CAT-07/08), tax rates (CAT-04 settings page), message templates (NTF-03), team
notification settings, account settings (ACC-06), data export page (INS-02), legal pages
(MKT-03), contact page (MKT-02), the client visit page (JOB-05), and per-business payment
onboarding (PAY-03). These follow the same patterns and can be added as their specs come up.

## Assets

- `assets/shadetree.css`: tokens and components.
- `assets/icons.js`: inline SVG icon set (Feather-style strokes).
- `assets/app.js`: shell and interactions.
- `assets/fonts/`: Public Sans, self-hosted (SIL OFL 1.1, see `OFL.txt`).
