# Shadetree outgoing email (both environments) through Amazon SES, from getshadetree.com.
#
# - Domain identity getshadetree.com with Easy DKIM (3 CNAME records in the getshadetree.com zone).
# - Custom MAIL FROM domain mail.getshadetree.com (MX + SPF), so SPF aligns for DMARC without
#   touching the apex SPF record (shadetree_email.tf).
# - DMARC at _dmarc.getshadetree.com, reports to dmarc@ (forwarded to the human inbox).
# - Configuration set "shadetree": no open/click tracking (it would rewrite client links), bounces
#   and complaints go on SES's suppression list.
# - One IAM user per environment that may only send From no-reply@getshadetree.com. Its SMTP
#   password is derived for var.aws_region; `terraform output` shows the values (infra/README.md).
#
# Manual, once (infra/README.md, "Outgoing email (Amazon SES)"): request production access for
# SES. Until then SES only delivers to verified addresses (var.ses_sandbox_recipients), 200 a day.
#
# State holds the SMTP passwords (GCS backend, encrypted).

locals {
  ses_domain       = "getshadetree.com"
  ses_mail_from    = "mail.getshadetree.com"
  ses_from_address = "no-reply@getshadetree.com"
  shadetree_envs   = toset(["staging", "production"])
}

data "aws_caller_identity" "current" {}

resource "aws_sesv2_configuration_set" "shadetree" {
  configuration_set_name = "shadetree"

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  # We don't configure delivery options. SES reports max_delivery_seconds as 0 (unset), which
  # Terraform plans as "0 -> null" on every run (the valid range is 300-50400, so 0 can't be set
  # in config). That perpetual update also made the IAM policy document below "known after apply",
  # because it reads this resource's ARN, and showed up as a policy change on both IAM users.
  lifecycle {
    ignore_changes = [delivery_options]
  }
}

resource "aws_sesv2_email_identity" "getshadetree" {
  email_identity         = local.ses_domain
  configuration_set_name = aws_sesv2_configuration_set.shadetree.configuration_set_name

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

resource "cloudflare_record" "getshadetree_ses_dkim" {
  count   = 3
  zone_id = var.getshadetree_zone_id
  name    = "${aws_sesv2_email_identity.getshadetree.dkim_signing_attributes[0].tokens[count.index]}._domainkey"
  content = "${aws_sesv2_email_identity.getshadetree.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"
  type    = "CNAME"
  proxied = false
  ttl     = 3600
}

resource "aws_sesv2_email_identity_mail_from_attributes" "getshadetree" {
  email_identity         = aws_sesv2_email_identity.getshadetree.email_identity
  mail_from_domain       = local.ses_mail_from
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "cloudflare_record" "getshadetree_ses_mail_from_mx" {
  zone_id  = var.getshadetree_zone_id
  name     = "mail"
  content  = "feedback-smtp.${var.aws_region}.amazonses.com"
  type     = "MX"
  priority = 10
  ttl      = 3600
}

resource "cloudflare_record" "getshadetree_ses_mail_from_spf" {
  zone_id = var.getshadetree_zone_id
  name    = "mail"
  content = "v=spf1 include:amazonses.com ~all"
  type    = "TXT"
  ttl     = 3600
}

resource "cloudflare_record" "getshadetree_dmarc" {
  zone_id = var.getshadetree_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=none; rua=mailto:dmarc@getshadetree.com"
  type    = "TXT"
  ttl     = 3600
}

# Addresses SES may deliver to while the account is in the sandbox (each gets a verification
# email). Only in terraform.tfvars, never committed.
resource "aws_sesv2_email_identity" "ses_sandbox_recipient" {
  for_each       = toset(var.ses_sandbox_recipients)
  email_identity = each.value
}

# Send only, only From no-reply@getshadetree.com. identity/* rather than the domain alone: in the
# sandbox SES also authorizes against the (verified) recipient identities.
data "aws_iam_policy_document" "shadetree_ses_send" {
  statement {
    actions = ["ses:SendRawEmail"]
    resources = [
      "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
      aws_sesv2_configuration_set.shadetree.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [local.ses_from_address]
    }
  }
}

resource "aws_iam_user" "shadetree_smtp" {
  for_each = local.shadetree_envs
  name     = "shadetree-${each.key}-smtp"
}

resource "aws_iam_user_policy" "shadetree_smtp" {
  for_each = local.shadetree_envs
  name     = "ses-send-no-reply"
  user     = aws_iam_user.shadetree_smtp[each.key].name
  policy   = data.aws_iam_policy_document.shadetree_ses_send.json
}

resource "aws_iam_access_key" "shadetree_smtp" {
  for_each = local.shadetree_envs
  user     = aws_iam_user.shadetree_smtp[each.key].name
}

output "shadetree_smtp_address" {
  value = "email-smtp.${var.aws_region}.amazonaws.com"
}

output "shadetree_smtp_username" {
  value = { for env, key in aws_iam_access_key.shadetree_smtp : env => key.id }
}

output "shadetree_smtp_password" {
  value     = { for env, key in aws_iam_access_key.shadetree_smtp : env => key.ses_smtp_password_v4 }
  sensitive = true
}
