# Stripe setup (BIL-04, docs/runbooks/stripe.md). Run after deploying a plan change, in test mode
# (staging) and live mode (production) alike:
#   bin/rails stripe:sync_plans
# Creates or updates a product per paid plan, its monthly and yearly prices (by lookup key) and
# the customer portal's settings. Safe to run again; it changes only what differs.
namespace :stripe do
  desc "Create or update Stripe products, prices and portal settings from the plans"
  task sync_plans: :environment do
    abort "Set STRIPE_SECRET_KEY first (see docs/runbooks/stripe.md)." unless Billing.configured?

    puts "Syncing plans to Stripe (#{Billing.live_mode? ? "live" : "test"} mode)…"
    host = ENV["APP_HOST"].presence
    log = Billing::PlanSync.new(return_url: host && "https://#{host}/admin/plan").run!
    puts log.any? ? log.map { "  #{_1}" } : "  Already up to date."
  end
end
