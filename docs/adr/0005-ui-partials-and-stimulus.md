# 0005. UI building blocks as partials and helpers, behavior in Stimulus

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-05, and every spec with UI

## Context

PLT-05 calls for a small kit of reusable UI pieces: buttons, form fields, tables, cards, badges,
modals, empty states and so on. The original docs assumed ViewComponent. The app is
server-rendered with Hotwire, and the vision rules out a client-side framework.

## Options considered

1. **ViewComponent.** Testable Ruby objects with templates, good for large component libraries.
   But it adds a dependency and a second way to render views, and it's heavier than our small
   kit needs.
2. **Phlex.** Views written in Ruby. Fast and composable, but unfamiliar to most Rails
   developers and agents, and it would mean rewriting every template.
3. **Rails partials plus small view helpers**, with **Stimulus** controllers for behavior
   (modals, menus, live totals) and Turbo for page updates.

## Decision

Build the kit as **partials under `app/views/components/`** with thin helpers where they make
call sites clearer, styled with Tailwind (ADR 0004). Interactive behavior goes in **Stimulus**
controllers, and page updates use **Turbo** frames and streams. No client-side framework.

If partials become hard to test or reason about, a later ADR may adopt ViewComponent for those
pieces only.

## Consequences

- Zero new dependencies, and the pattern every Rails developer and agent already knows.
- Components are tested through helper, controller and system tests, not as isolated objects.
- A development-only style guide page (PLT-05) shows every component and state.
- **Cost:** none.
