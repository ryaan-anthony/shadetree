# Shadetree's own cloud config: SES for outgoing email, Email Routing and the support-email
# Worker for incoming email, and their getshadetree.com DNS records (ADR 0027).
# Run by hand from this directory; no CI applies it. See README.md here.
#
# State: the homelab's existing bucket, under this repository's own prefix. If Shadetree
# moves to its own cloud account, migrate with `terraform init -migrate-state` to a new bucket.

terraform {
  backend "gcs" {
    bucket = "tf-state-hostilecity"
    prefix = "shadetree/infra"
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
