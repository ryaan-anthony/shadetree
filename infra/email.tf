# Shadetree support email (OPS-05, Shadetree ADR 0021), zone getshadetree.com.
#
# One Worker per Shadetree environment, each forwarding a copy to the human inbox and posting the
# raw message, signed with that environment's secret, to that environment's app:
#   production  support@getshadetree.com          -> https://getshadetree.com/inbound/support_email
#   staging     support-staging@getshadetree.com  -> https://staging.getshadetree.com/inbound/support_email
# (and their +<token> reply addresses once subaddressing is on). Staging's app needs
# SUPPORT_EMAIL=support-staging@getshadetree.com so its reply addresses come back to staging.
# The apex is used for both: staging.getshadetree.com is the tunnel's CNAME, which can't also hold
# MX records.
# privacy@, legal@, security@ and dmarc@ (DMARC reports) are forwarded straight to the human inbox.
#
# Manual, once (infra/README.md, "Support email"): enable Email Routing for the zone in the
# dashboard (it adds and locks the MX records; don't add its SPF record, see getshadetree_spf
# below), and turn on subaddressing. Provider 4.x can do neither without side effects:
# cloudflare_email_routing_settings enables routing through the API call that adds Cloudflare's
# own SPF record (a second SPF record breaks outgoing DMARC), and has no subaddressing setting.
#
# State holds shadetree_inbound_email_secrets and getshadetree_human_inbox (GCS backend, encrypted).

locals {
  shadetree_inbound = {
    production = {
      address = "support@getshadetree.com"
      url     = "https://getshadetree.com/inbound/support_email"
    }
    staging = {
      address = "support-staging@getshadetree.com"
      url     = "https://staging.getshadetree.com/inbound/support_email"
    }
  }
}

resource "cloudflare_workers_script" "shadetree_support_email" {
  for_each           = local.shadetree_inbound
  account_id         = var.cloudflare_account_id
  name               = "shadetree-support-email-${each.key}"
  content            = file("${path.module}/support-email-worker/src/worker.js")
  module             = true
  compatibility_date = "2026-11-01"

  plain_text_binding {
    name = "APP_INBOUND_URL"
    text = each.value.url
  }

  secret_text_binding {
    name = "HUMAN_INBOX"
    text = var.getshadetree_human_inbox
  }

  secret_text_binding {
    name = "INBOUND_EMAIL_SECRET"
    text = var.shadetree_inbound_email_secrets[each.key]
  }
}

# Cloudflare emails this address a verification link when it's created; forwarding (from the
# rules below and from the Worker) only works once it's been clicked.
resource "cloudflare_email_routing_address" "getshadetree_human_inbox" {
  account_id = var.cloudflare_account_id
  email      = var.getshadetree_human_inbox
}

resource "cloudflare_email_routing_rule" "getshadetree_support" {
  for_each = local.shadetree_inbound
  zone_id  = var.getshadetree_zone_id
  name     = "${each.value.address} to the shadetree-support-email-${each.key} Worker"
  enabled  = true
  priority = 0

  matcher {
    type  = "literal"
    field = "to"
    value = each.value.address
  }

  action {
    type  = "worker"
    value = [cloudflare_workers_script.shadetree_support_email[each.key].name]
  }
}

resource "cloudflare_email_routing_rule" "getshadetree_forward" {
  for_each = toset(["privacy", "legal", "security", "dmarc"])
  zone_id  = var.getshadetree_zone_id
  name     = "${each.value}@ to the human inbox"
  enabled  = true
  priority = 10

  matcher {
    type  = "literal"
    field = "to"
    value = "${each.value}@getshadetree.com"
  }

  action {
    type  = "forward"
    value = [cloudflare_email_routing_address.getshadetree_human_inbox.email]
  }
}

# The zone's ONE apex SPF record, for Cloudflare Email Routing. Outgoing mail (Amazon SES,
# shadetree_ses.tf) uses the mail.getshadetree.com MAIL FROM domain with its own SPF record, so the
# apex needs no SES include. Import an existing apex SPF record before the first apply (infra/README.md).
resource "cloudflare_record" "getshadetree_spf" {
  count   = var.getshadetree_spf == null ? 0 : 1
  zone_id = var.getshadetree_zone_id
  name    = "getshadetree.com"
  content = var.getshadetree_spf
  type    = "TXT"
  ttl     = 3600
}
