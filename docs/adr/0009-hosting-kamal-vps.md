# 0009. Kamal on a VPS, with managed PostgreSQL

- **Status:** Accepted; superseded in part by [0023](0023-homelab-vms-and-cloudflare-tunnel.md) (Kamal, VPSs and the registry)
- **Date:** 2026-11-14
- **Specs:** PLT-09, PLT-10

## Context

Launch hosting must stay under about $50/month for staging and production together. The app
already has a Kamal 2 config with placeholder hosts, plus a Dockerfile and Thruster. ADR 0002
moves the database to managed PostgreSQL, and ADR 0010 needs headless Chrome available for PDFs.

## Options considered

1. **A PaaS** (Render, Fly.io, Heroku-style). Least operations work, but costs roughly $50–100
   a month once web, worker, database and staging are included, and limits on running Chrome.
2. **Kubernetes or a managed container service.** Far more than a single small app needs.
3. **Kamal 2 deploying the Docker image to a small VPS per environment** (2–4 GB RAM), with
   managed PostgreSQL from the same provider. TLS comes from Kamal's proxy.

## Decision

Deploy with **Kamal 2** to **one VPS for production and one smaller VPS for staging**, with
**managed PostgreSQL** (ADR 0002) and object storage (ADR 0008). Solid Queue runs inside Puma
(ADR 0007). Images go to GitHub Container Registry.

The provider (for example Hetzner or DigitalOcean) is picked in PLT-09. Choose one that offers
both VPS and managed PostgreSQL in the same region.

## Consequences

- We own OS updates and the box. Kamal and the Docker image keep that small, and the runbook
  (PLT-09) covers it.
- Scaling is vertical first (a bigger VPS), then a second web host behind Kamal's proxy.
- Secrets come from Kamal secrets or the CI secret store, never the repository.
- **Cost (estimate):** production VPS about $10–20, staging VPS about $5–10, managed PostgreSQL
  about $15–30, storage under $1. That's about $30–60/month, at or slightly over the target; the
  open question is whether staging can share the production database server with a separate
  database.
