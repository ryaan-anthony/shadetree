# Stripe, for subscription billing (BIL-04) and client payments (PAY-03/04): this file is shared
# by both, so keep it to these lines. Keys come from the environment only
# (docs/runbooks/stripe.md); the API version is pinned so a gem update can't change what the
# app receives. Short timeouts and one retry: Stripe is called from requests and jobs, never
# while a business row is locked. The app talks to Stripe through StripeGateway.
Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
Stripe.api_version = "2026-11-18.endive"
Stripe.set_app_info("Shadetree", url: "https://getshadetree.com")
Stripe.open_timeout = 5
Stripe.read_timeout = 15
Stripe.max_network_retries = 1
