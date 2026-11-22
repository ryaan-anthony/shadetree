# #314 admin design-system audit: triage against main

The audit (#314) was a read-only look at staging on 2026-11-21, before #289's UX PRs merged
(#292, #298, #299, #301, #302, #303). This file checks each finding against `main` at c8ecf8d1
(2026-11-22), using the code and the dev seeds in a browser at 1280 and 390 px. What's still
true is grouped into specs PLT-14 to PLT-19 ([01-platform](../plans/01-platform.md) R23–R28).

**Status:** **Fixed** means already fixed on main, with the PR. "Not reproducible" means the
markup was already right. **Still true** means the finding holds as written. **Partly true**
means some of it holds, or it holds somewhere else.

## Summary

| Status | Count |
| --- | --- |
| Fixed (incl. 3 not reproducible) | 13 |
| Still true | 33 |
| Partly true | 18 |
| **Total** (the 13 items split into findings, plus the token and narrow-screen notes) | 64 |

## Findings

Paths are under `app/`. Line numbers are at c8ecf8d1.

| # | Finding | Status | Evidence | Spec |
| --- | --- | --- | --- | --- |
| 1a | Quote page's primary is navigation ("Job J-0002") | Still true | `views/admin/quotes/show.html.erb:7` | PLT-14 |
| 1b | Client page: "New quote" bordered, "New invoice"/"New job" text links | Still true | `views/admin/clients/show.html.erb:71-73` | PLT-14 |
| 1c | "Cancel job" is plain grey | Still true | `views/admin/jobs/show.html.erb:12` (ghost; only the dialog's confirm is red, :24) | PLT-14 |
| 1d | Home has no primary | Partly true | #301 rebuilt Home; its only primary is the tour offer while shown | PLT-14 (question) |
| 2a | H2s indistinguishable from body bold | Partly true | Card titles are 15 px/650 vs 14 px body; one-offs at 14 px/600 ("What they need", "Client response") | PLT-15 |
| 2b | Home stat "2 of 5" in mixed sizes | Fixed (#292, #301) | Home: "3 / Of your 30 Starter quotes this billing period" | — |
| 2c | Quote document title outranks the H1 | Partly true | It equals it: both 22 px/700, same text (`views/admin/quotes/show.html.erb:105`) | PLT-15, PLT-16 |
| 2d | "Sent … by …" set as an H2 | Still true | Quote and invoice pages' sent panel (measured H2, 14 px/600) | PLT-15 |
| 2e | Plan "(not included)" double negative | Fixed (#280) | Plan now says "Not included" | — |
| 3a | Top bar repeats the page title above the H1 | Still true | `views/layouts/app.html.erb:24` | PLT-15 |
| 3b | Schedule H1 "Schedule: November 16 – 22, 2026" | Still true | Follows the owner's #274 decision (heading has "Schedule" and the year) | PLT-15 (question) |
| 3c | Payments: "Payments" in the bar, "Settings" as H1 | Still true | Also Plan and Your data. #302 kept "Settings" as the H1 | PLT-15 |
| 4a | Forms are a narrow column beside empty space | Partly true | #303 added the form-plus-summary layout to Log a request, visit and payment forms; others still use ad-hoc widths (20× `max-w-2xl`, 12× `3xl`, 10× `xl`, …) | PLT-16 |
| 4b | Home and My day leave the screen empty | Partly true | Home fixed by #301 (two across); My day is still one `max-w-2xl` column | PLT-16 (question) |
| 4c | Rail cards wrap dates and cut text mid-word | Still true | Invoice Payments: "Nov 22, / 2026"; quote Invoices card: "Due Dec 6, 202…" | PLT-16 |
| 5a | Quote page repeats status, dates and total 2–3 times | Still true | Strip `views/admin/quotes/show.html.erb:73-76`, then the client document card :105 | PLT-16 |
| 5b | Invoice balance in the strip and the Payments card | Still true | `views/admin/invoices/show.html.erb:37`, `views/admin/invoices/_payments.html.erb:33` | PLT-16 |
| 5c | Client page repeats an invoice in Work, Timeline and Balance | Partly true | Timeline lists payment events, not the invoice total; Work and Balance overlap less | PLT-16 |
| 6a | Approved and Paid are the same green pill | Still true | `helpers/quotes_helper.rb:5`, `helpers/invoices_helper.rb:3` | PLT-17 (question) |
| 6b | Status tones chosen per record type | Still true | Three maps plus one inline. A request's "In progress" is amber on its page (`views/admin/service_requests/show.html.erb:15`) and grey on the client page (`views/admin/clients/show.html.erb:81`) | PLT-17 |
| 6c | Owner is the only dark pill | Still true | `views/admin/team/show.html.erb:23` | PLT-17 |
| 6d | One failed email gets three severities | Still true | Red banner (`views/admin/sends/_delivery_warning.html.erb`), amber icon (`views/admin/clients/show.html.erb:158`, `_timeline_events.html.erb:6`), plain icon in Notifications | PLT-17 |
| 6e | Green is both the primary button and the "done" pill | Still true | By design. Kept, with green pills only for "done" | PLT-17 |
| 7a | Quantity in two tones; three quantity styles | Still true | Quote "Qty 1", invoice "1 × $240.00", services "$45.00 / visit" with a muted unit | PLT-18 |
| 7b | Jobs list: Value right-aligned, From not | Still true | `views/admin/jobs/_results.html.erb:52` (From is a document number, so left-aligned is arguably right) | PLT-18 |
| 7c | Relative and absolute dates mixed | Still true | Quotes list's date column mixes "Updated 5 minutes ago" and "Nov 22, 2026" | PLT-18 |
| 7d | Phones formatted inconsistently | Partly true | #298 fixed cards, job, request, locations and settings. The Clients list shows them as typed (`views/admin/clients/_results.html.erb:47,76`): "555.380.3141" beside "(555) 380-1200" | PLT-18 |
| 7e | Zero shown as "—" in lists, "$0.00" elsewhere | Still true | `views/admin/jobs/_results.html.erb:35,64`, `views/admin/invoices/_results.html.erb:64` | PLT-18 |
| 8a | "Paid in all:$75.00" (missing space) | Fixed (not reproducible) | The space is in the markup since #188 (`views/admin/clients/show.html.erb:181`); screen and text read "Paid in all: $178.70" | PLT-18 (guard test) |
| 8b | "Couldn't send(…" and "Emailed …by" | Fixed (not reproducible) | `views/admin/sends/_history.html.erb:8-10` (#184) has the spaces | PLT-18 (guard test) |
| 8c | "In Eastern Time (US & Canada) time." | Partly true | Hours says "Times are in …". The visit form's arrival note still says it (`views/admin/shared/_arrival_fields.html.erb:16`) | PLT-18 |
| 8d | Internal IDs shown (R-…, CAT-07, "Quote version 26") | Fixed (#298) | References are behind "Reference" | — |
| 8e | New: Stripe payment IDs on job page and client timeline | Still true | `views/admin/jobs/show.html.erb:70`; timeline "(pi_demoOakline0001)" | PLT-18 |
| 8f | Mowing placeholder in a pest-control business | Fixed (#298) | Examples come from the business's industry preset | — |
| 8g | "0 of 0" automations | Fixed (#280) | `helpers/billing_helper.rb:7` | — |
| 8h | "Nobody yet 0 visits" on Schedule | Fixed (#298) | "Not assigned · 1 visit" | — |
| 8i | "Showing 1–2 of 2" with a bold range | Still true | `views/components/_pagination.html.erb:3` | PLT-18 |
| 9a | 8-tab rows, most at 0 | Still true | Quotes and Jobs show 8 tabs, Invoices 6 | PLT-19 |
| 9b | Services tabs right-aligned | Still true | `views/admin/catalog_items/index.html.erb:16` | PLT-19 |
| 9c | Four switch styles | Still true | Schedule's "Color by" (`views/admin/schedule/show.html.erb:47-50`), Plan's Monthly/Yearly (`views/admin/plans/show.html.erb:41-48`), Day/Week as tabs, and #302's settings pills as a fifth | PLT-19 |
| 9d | Services has a Search button; other lists search as you type | Still true | `views/admin/catalog_items/index.html.erb:14` | PLT-19 |
| 9e | Settings: 11 tabs, a URL each | Fixed (#302) | Four groups. Old URLs kept by design | — |
| 10a | Too many button variants | Still true | 7 variants: `helpers/components_helper.rb:4` | PLT-14 |
| 10b | Cancel is a link on forms | Partly true | Cancel is the borderless button everywhere seen; consistent, but not a written rule | PLT-14 |
| 10c | Empty-state CTA duplicates the page's (Taxes) | Fixed (#280) | Top "Add a tax rate" only once rates exist | — |
| 10d | Disabled Previous/Next look enabled | Partly true | Kit dims to 50% (`assets/tailwind/components.css:26-27`). Clients has its own pager; both show on one-page lists | PLT-14 |
| 10e | Move arrows fade to near-invisible | Still true | `views/admin/catalog_items/index.html.erb:67-68` | PLT-14 |
| 11a | Automations empty states are plain text | Still true | `views/admin/automations/index.html.erb:17,63` | PLT-19 |
| 11b | Empty schedule week has no message | Fixed (#299) | "Nothing booked this week" and the next visit (`views/admin/schedule/show.html.erb:21`) | — |
| 11c | Home "Nothing booked today." is plain text | Still true | `views/admin/dashboard/_today.html.erb:15,36` (and My day) | PLT-19 |
| 11d | Unread notifications only a tint | Partly true | #280 added an "Unread" label; titles have the same weight as read ones | PLT-19 |
| 12a | Admin vs business brand colour is unexplained | Partly true | Branding says "everything clients see" but not that the admin stays green | PLT-19 (question) |
| 12b | Logo upload is the browser's file control | Still true | Settings → Branding ("Choose File No file chosen") | PLT-19 |
| 12c | Placeholder logo instead of an initials mark | Fixed (not reproducible) | No logo already shows the business's initials in its colour (sidebar, preview); staging had an uploaded image | — |
| 13a | Toast | Partly true | One toast component exists (success fades after 6 s, errors stay); usage rules not written down | PLT-19 |
| 13b | Banner | Partly true | One banner component with four tones; usage rules not written | PLT-19 |
| 13c | Menu item "Duplicate for another client" wraps | Still true | `views/admin/quotes/show.html.erb:39`. "Duplicate" is already another item, so the label can't simply be shortened | PLT-18 |
| T1 | Colours not locked to tokens | Still true | ~70 hex values in the kit's stylesheet outside the tokens (calendar tones, borders, hovers); one in Branding's preview | PLT-17 |
| T2 | Washed-out muted text | Fixed (#280) | `muted` is #5e6d82 (AA on white, canvas and sunken) | — |
| T3 | Initials avatars in client rows | Still true (suggestion) | No avatars in lists | PLT-19 (question) |
| T4 | Timeline icons vary in colour by meaning | Partly true | Neutral except bounced email (amber) | PLT-17 |
| T5 | Rails dense, metadata loud | Partly true | Matches 4c and 5a–5b | PLT-16 |
| M1 | Narrow screens (inferred, not tested by the audit) | Partly true | At 390 px: the sidebar is a drawer, tab rows scroll sideways and tables stack (checked on Quotes, a quote and Clients). Each spec includes phone checks | all |
| M2 | Spacing and radius tokens to lock | Partly true | Radius tokens exist (control 6 px, card 10 px, dialog 14 px); spacing uses Tailwind's 4 px scale. No change proposed | — |
