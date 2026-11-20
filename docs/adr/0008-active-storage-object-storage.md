# 0008. Active Storage on S3-compatible object storage

- **Status:** Accepted; superseded in part by [0023](0023-homelab-vms-and-cloudflare-tunnel.md) (object storage)
- **Date:** 2026-11-14
- **Specs:** CAT-02, CLI-03, QTE-01, JOB-04, INS-02, PLT-09

## Context

Businesses upload logos. Clients attach photos to requests. Technicians add job photos from
phones. Exports bundle files. Today a `logo_url` text field is the only file handling. Files
must survive redeploys and server loss, be backed up, and stay cheap at free-tier volume.
Photos are viewed often, so egress (download) costs matter.

## Options considered

1. **Local disk on the VPS** (a Docker volume). Free, but tied to one server, backed up only if
   we do it, and lost if the volume is.
2. **Amazon S3.** The standard, but egress fees add up for photo-heavy pages.
3. **S3-compatible storage with no egress fees** (for example Cloudflare R2), through Active
   Storage's S3 service.

## Decision

Use **Active Storage** for all uploads. Production and staging use an **S3-compatible bucket with
free egress** (Cloudflare R2 recommended; any S3-compatible provider works through
configuration). Development and test use local disk. Images get size and type validation,
location metadata stripped, and web-sized variants (PLT-13).

## Consequences

- Image variants need `image_processing` with libvips in the container image.
- Per-plan limits on photo count and size (BIL-01) are enforced in the app.
- Backups: the bucket's versioning or lifecycle rules, documented in the PLT-09 runbook.
- **Cost:** about $0.015/GB-month with no egress fees; under $1/month at launch.
