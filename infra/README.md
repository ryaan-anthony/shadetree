# Shadetree infrastructure

Shadetree's own cloud config: outgoing email through Amazon SES, incoming support email through Cloudflare Email Routing and the `support-email-worker` Worker, and their getshadetree.com DNS records ([ADR 0026](../docs/adr/0026-cloud-config-in-this-repository.md)). The VMs, the tunnel and PostgreSQL are in the op-works repository; this directory is only what belongs to the app.

It is run **by hand** from a laptop. No CI applies it, and no workflow here needs a self-hosted runner.

```
gcloud auth application-default login     # the state bucket
export AWS_PROFILE=hostilecity            # SES and IAM (see "Outgoing email")
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

`infra/terraform.tfvars` holds the values (never commit it; it is ignored). It needs `cloudflare_api_token`, `cloudflare_account_id`, `getshadetree_zone_id`, `getshadetree_human_inbox`, `getshadetree_spf` and `shadetree_inbound_email_secrets`, and optionally `aws_region` and `ses_sandbox_recipients`.

State is in the homelab's GCS bucket under the prefix `shadetree/infra`. It holds the SMTP passwords, the inbound-email secrets and the human inbox address: the bucket is encrypted and access-controlled, so keep it that way.

## Moving here from op-works (one time)

Until this lands, these resources were in op-works' `tf-config/`. Move their state, then op-works removes the files (its issue #54):

```
infra/bin/move-from-op-works.sh ~/path/to/op-works            # dry run: lists the moves
infra/bin/move-from-op-works.sh ~/path/to/op-works --apply    # backs up both states, moves, pushes
terraform -chdir=infra plan                                    # No changes
```

Only state moves, so nothing in AWS or Cloudflare is recreated, and the SMTP access keys keep their secrets. Copy the email variables from op-works' `tf-config/terraform.tfvars` into `infra/terraform.tfvars` first. The script refuses if op-works' state holds anything that isn't Shadetree's, or if `infra/` already has state. Backups go to `~/shadetree-state-backups/<timestamp>/`.

## Support email

Each Shadetree environment has its own support address and its own copy of the
`support-email-worker` Worker in this directory, deployed by `email.tf`.
Each Worker forwards a copy to the human inbox and posts the message to that environment's app,
signed with that environment's secret (OPS-05, Shadetree ADR 0021).

| Environment | Address | Worker | Posts to |
| --- | --- | --- | --- |
| production | `support@getshadetree.com` | `shadetree-support-email-production` | `https://getshadetree.com/inbound/support_email` |
| staging | `support-staging@getshadetree.com` | `shadetree-support-email-staging` | `https://staging.getshadetree.com/inbound/support_email` |

Both addresses are on the apex, because `staging.getshadetree.com` is the tunnel's CNAME and can't
also have MX records. Their `+<token>` reply addresses reach the same Worker. privacy@, legal@, security@ and dmarc@ are forwarded to the human inbox.
The app side is described in [`docs/runbooks/inbound-email.md`](../docs/runbooks/inbound-email.md).

The Cloudflare API token (`cloudflare_api_token`) needs these permissions, for this directory:

- Account: Workers Scripts Edit, Email Routing Addresses Edit
- Zone getshadetree.com: Email Routing Rules Edit, DNS Edit, Zone Settings Edit (for the subaddressing call)

Terraform state holds `shadetree_inbound_email_secrets` and `getshadetree_human_inbox`. The GCS
backend is encrypted and access-controlled; keep it that way.

- Add to `infra/terraform.tfvars` (never commit it):

```
cloudflare_account_id          = "<account id>"
getshadetree_zone_id           = "<getshadetree.com zone id>"
getshadetree_human_inbox       = "<human support inbox>"
getshadetree_spf               = "v=spf1 include:_spf.mx.cloudflare.net ~all"
shadetree_inbound_email_secrets = {
  production = "<production's INBOUND_EMAIL_SECRET>"
  staging    = "<staging's INBOUND_EMAIL_SECRET>"
}
```

Generate one secret per environment, and set each one on the matching GitHub environment of
ryaan-anthony/shadetree as the secret `INBOUND_EMAIL_SECRET`:

```
openssl rand -hex 32
```

On the `staging` GitHub environment, also set the variable
`SUPPORT_EMAIL` = `support-staging@getshadetree.com`, so staging's reply addresses come back to
staging. Leave it unset on production, where the default is `support@getshadetree.com`.

**Cloudflare Access on staging:** add `/inbound/` to the staging bypass application (next to
`/webhooks/`). Otherwise the staging Worker's posts get Access's login page.

- Enable Email Routing for getshadetree.com in the dashboard (Email > Email Routing). Accept
   its MX records but **not** its SPF record: the zone must keep exactly one SPF record. Remove
   MX records from any other inbound mail host first.

- Turn on subaddressing (required: without it every emailed reply to a `support+<token>@`
   address bounces once the app's `INBOUND_EMAIL_ENABLED` is on). Provider 4.x can't set it.
   Use Email Routing > Settings > Subaddressing in the dashboard, or:

```
curl https://api.cloudflare.com/client/v4/zones/$GETSHADETREE_ZONE_ID/email/routing \
  -X PATCH -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -d '{"support_subaddress": true}'
```

- Bring the existing SPF record under Terraform (the record id is in the dashboard or
   `GET /zones/<zone id>/dns_records?type=TXT`):

```
terraform -chdir=infra import 'cloudflare_record.getshadetree_spf[0]' <zone id>/<record id>
```

- Plan and apply. On the first plan, check that each support rule's `worker` action takes its
   script's name, and that the apex SPF record is only Cloudflare's include:

```
terraform -chdir=infra plan
terraform -chdir=infra apply
```

- Click the verification link Cloudflare emails to the human inbox. Forwarding fails until then.

- Check that there's exactly one SPF record, then that outgoing app email still passes DMARC:

```
dig +short TXT getshadetree.com | grep -c 'v=spf1'
```

- Test staging first. Redeploy staging, then send an email from a staging member's address to
   `support-staging@getshadetree.com`. The human inbox gets a copy, and a ticket opens on staging.
   Set `INBOUND_EMAIL_ENABLED=true` on staging, redeploy, and reply to a support email from
   staging: the reply should go to `support-staging+…@getshadetree.com` and thread into the ticket.
   Then do the same on production with `support@getshadetree.com`.

Test the Worker (Node 20+, no install):

```
cd infra/support-email-worker && node --test
```

To rotate an environment's secret, change its entry in `shadetree_inbound_email_secrets` and that
environment's `INBOUND_EMAIL_SECRET` within minutes of each other. Mail that arrives in between still reaches
the human inbox. On a proxy or tunnel in front of the app, allow request bodies of about
26 MiB on `/inbound/support_email`.

## Outgoing email (Amazon SES)

Shadetree (staging and production) sends email over SMTP through Amazon SES, from
`no-reply@getshadetree.com`. `ses.tf` manages:

- the SES domain identity `getshadetree.com`, with Easy DKIM
- a custom MAIL FROM domain, `mail.getshadetree.com`
- DMARC
- a configuration set with no open or click tracking, which sends bounces and complaints to the suppression list
- one IAM user per environment that may only send from `no-reply@getshadetree.com`

The DNS records go in the getshadetree.com zone through Cloudflare.

**AWS credentials for Terraform.** Use an IAM user or SSO role that can manage SES (`ses:*`) and IAM
users (`iam:*User*`, `iam:*AccessKey*`, `iam:*UserPolicy*`). For example:

```
aws sso login --profile hostilecity
export AWS_PROFILE=hostilecity
```

- **Optional:** add to `infra/terraform.tfvars`. The default region is `us-east-1`. The
  recipients are addresses SES may email while the account is in the sandbox, and each one gets a
  verification link:

```
aws_region             = "us-east-1"
ses_sandbox_recipients = ["<your test inbox>"]
```

- **If `_dmarc.getshadetree.com` already exists,** import it first:

```
terraform -chdir=infra import cloudflare_record.getshadetree_dmarc <zone id>/<record id>
```

- **Plan and apply.** Run `init` first:

```
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

- **Wait for SES to verify the domain** (DKIM). It usually takes a few minutes, and up to 72 hours.
  The console's Identities page shows getshadetree.com as **Verified**. The MAIL FROM domain shows
  **Success** once its MX record resolves.

- **Click the verification link** each sandbox recipient receives.

- **Request production access.** Go to the SES console → Account dashboard → **Request production
  access** and describe the use: transactional email for a business app (sign-up, password reset,
  quotes, invoices, receipts), with bounces and complaints suppressed automatically. Until it's
  approved, SES delivers only to verified addresses, up to 200 a day. Staging is fine in the
  sandbox. Production needs the approval before launch.

- **Put the SMTP settings in each GitHub environment** of `ryaan-anthony/shadetree`
  (`staging`, `production`):

```
terraform -chdir=infra output shadetree_smtp_address           # SMTP_ADDRESS (variable)
terraform -chdir=infra output -json shadetree_smtp_username    # SMTP_USERNAME (secret), per environment
terraform -chdir=infra output -json shadetree_smtp_password    # SMTP_PASSWORD (secret), per environment
```

  The other values: `SMTP_PORT` = `587` (STARTTLS) and
  `MAIL_FROM` = `Shadetree <no-reply@getshadetree.com>`. Then redeploy (Actions → Deploy → Run
  workflow).

- **Check delivery.** Sign up on staging with an allowed address, then check that the email's
  headers show `dkim=pass` for getshadetree.com, `spf=pass` for mail.getshadetree.com, and
  `dmarc=pass`:

```
dig +short TXT _dmarc.getshadetree.com
dig +short MX mail.getshadetree.com
```

**Rotating the SMTP password.** Replace that environment's key, then update the secret and
redeploy:

```
terraform -chdir=infra apply -replace='aws_iam_access_key.shadetree_smtp["staging"]'
```

**Things to know:**

- State holds both SMTP passwords. The GCS backend is encrypted and access-controlled.
- The SMTP password is tied to `aws_region`, so changing the region means new keys.
- Every Terraform run here needs AWS credentials as well as GCP (for the state) and Cloudflare.
- **Later:** tighten DMARC to `p=quarantine` once reports show only SES and Cloudflare sending
  for the domain.
