variable "cloudflare_api_token" {
  type = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type = string
}

variable "getshadetree_zone_id" {
  type = string
}

variable "getshadetree_human_inbox" {
  type = string
  sensitive = true
}

variable "getshadetree_spf" {
  type = string
  default = null
}

# Keys: production, staging. Each is that environment's INBOUND_EMAIL_SECRET.
variable "shadetree_inbound_email_secrets" {
  type      = map(string)
  sensitive = true
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ses_sandbox_recipients" {
  type    = list(string)
  default = []
}
