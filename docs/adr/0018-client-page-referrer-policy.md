# 0018. Client pages send Referrer-Policy: same-origin

- **Status:** Accepted
- **Date:** 2026-11-16
- **Specs:** QTE-05; amends [ADR 0016](0016-client-links.md)

## Context

ADR 0016 has client pages send `Referrer-Policy: no-referrer`, so a client link's token never
reaches another site in the `Referer` header. QTE-05 adds forms to the client page (approve,
decline, ask for changes). With `no-referrer`, browsers send `Origin: null` when a form submits
natively (not through Turbo's `fetch`), and Rails' CSRF protection refuses a request whose
Origin doesn't match. Integration tests can't see this: the test environment turns CSRF
protection off and test requests carry no Origin.

## Decision

- Client pages send `Referrer-Policy: same-origin`. Requests to our own pages carry the
  referrer and a real Origin; requests to any other site carry neither.
- A system test runs the client page's forms in a browser with CSRF protection on, so a header
  that breaks them fails CI.

## Consequences

- Tokens still never reach another site's `Referer`. Our own requests now carry a `Referer`
  with the token; the Rails request log doesn't record `Referer`, and no proxy log on the VMs
  records it either (ADR 0023; Cloudflare's URL logging stays off, as ADR 0016 says).
- Forms on client pages work whether or not Turbo submits them.
- **Cost:** none.
