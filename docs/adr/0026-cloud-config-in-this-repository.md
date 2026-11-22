# 0026. Shadetree's own cloud config lives in this repository

- **Status:** Accepted
- **Date:** 2026-11-22
- **Specs:** OPS-05, NTF-01, PLT-09; amends where [ADR 0021](0021-inbound-support-email.md) and [ADR 0023](0023-homelab-vms-and-cloudflare-tunnel.md) put things

## Context

The Terraform for Shadetree's SES sending, its Cloudflare Email Routing rules, the support-email Worker and their getshadetree.com DNS records lived in op-works, the owner's homelab repository, beside the VMs. op-works is narrowing to VMs, services and images (its ADR 0010), will become public, and should hold nothing an app owns. Shadetree is meant to become a business and later a private repository.

## Options considered

1. **Keep it in op-works**: one place for all Terraform. Mixes an app's cloud accounts and secrets into a homelab repository that is going public.
2. **Move it here, run by hand**: the app owns its email setup; the change is a state move with nothing recreated. Needs AWS and Cloudflare credentials on the laptop that runs it.
3. **Move it here and apply from CI**: hands-off, but puts AWS and Cloudflare credentials in GitHub and a self-hosted or cloud runner in the path.

## Decision

Option 2. `infra/` is a Terraform root with its own state (prefix `shadetree/infra` in the existing state bucket), holding `ses.tf`, `email.tf` and the Worker's source in `infra/support-email-worker/`. It is planned and applied by hand, documented in `infra/README.md`. The move from op-works is a `terraform state mv` between the two states (`infra/bin/move-from-op-works.sh`), so nothing is recreated and the SMTP access keys keep their secrets. The VMs, the tunnel and PostgreSQL stay in op-works.

## Consequences

- Email setup changes are reviewed in this repository's PRs, next to the app code that depends on them.
- The laptop that applies `infra/` needs GCP (state), AWS and Cloudflare credentials; CI needs none.
- The Cloudflare token for `infra/` needs only the getshadetree.com permissions, not hostilecity.net.
- Later: if Shadetree gets its own cloud account, move the state to its own bucket with `terraform init -migrate-state`.
- **Cost:** none.
