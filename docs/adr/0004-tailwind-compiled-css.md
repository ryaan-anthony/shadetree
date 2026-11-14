# 0004. Tailwind CSS compiled at build time

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-05, PLT-13

## Context

Every layout loads Tailwind from `cdn.tailwindcss.com` at runtime, with the theme copied into
each layout. That is slow (the CSS is generated in the browser), breaks a strict content
security policy (PLT-13), and lets the copies drift. The mockups in `docs/mockups` define one
token set (colors, type, spacing, radii) that the app should share.

## Options considered

1. **Keep the CDN.** No build step, but slow, CSP-hostile and not meant for production.
2. **Hand-written CSS** like the mockups' `shadetree.css`. Full control and no tooling, but
   every feature writes new CSS, and consistency depends on discipline.
3. **Tailwind compiled with the standalone CLI** (the `tailwindcss-rails` gem). Utility classes
   the team already uses, a single theme file for tokens, and output purged to the classes
   actually used. No Node.js required.

## Decision

Compile Tailwind at build time with `tailwindcss-rails`. Define the design tokens from
`docs/mockups/assets/shadetree.css` once in the Tailwind theme, and serve the output through
Propshaft with long-lived caching. Self-host the font (Public Sans) instead of loading it from a
font CDN. PLT-05 does the migration.

## Consequences

- `bin/dev` runs the Tailwind watcher alongside the server (a `Procfile.dev` returns).
- CI and the Docker build run the Tailwind build step.
- The layouts' inline theme configuration goes away.
- **Cost:** none; smaller, cacheable CSS also lowers bandwidth.
