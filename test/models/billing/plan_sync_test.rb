require "test_helper"

class Billing::PlanSyncTest < ActiveSupport::TestCase
  test "creates a product per paid plan, monthly and yearly prices by lookup key, and the portal settings" do
    log = Billing::PlanSync.new.run!

    paid = Plan.all.reject(&:free?)
    assert_equal paid.map(&:stripe_product_id).sort, stripe.products.keys.sort
    assert_nil stripe.products["shadetree_free"]
    monthly = stripe.prices.find { _1[:lookup_key] == "shadetree_starter_monthly" }
    assert_equal [ 1900, "usd", { interval: "month" }, "shadetree_starter" ], monthly.values_at(:unit_amount, :currency, :recurring, :product)
    assert_equal 19000, stripe.prices.find { _1[:lookup_key] == "shadetree_starter_yearly" }[:unit_amount]
    assert_includes log, "starter: product created"

    config = stripe.portal_configurations.sole
    assert_equal "shadetree_default", config.metadata["shadetree"]
    switchable = config.features.subscription_update.products.map(&:product)
    assert_equal Plan.listed.reject(&:free?).map(&:stripe_product_id), switchable
    assert_equal "at_period_end", config.features.subscription_cancel.mode
    assert_equal config.id, Billing::PlanSync.portal_configuration_id
  end

  test "running again changes nothing" do
    Billing::PlanSync.new.run!
    before = stripe.prices.size

    log = Billing::PlanSync.new.run!

    assert_equal before, stripe.prices.size
    assert_equal [ "customer portal: settings updated" ], log
    assert_equal 1, stripe.portal_configurations.size
  end

  test "a changed price gets a new price that takes the lookup key; the old one is archived" do
    Billing::PlanSync.new.run!
    old = stripe.prices.find { _1[:lookup_key] == "shadetree_starter_monthly" }
    plans(:starter).update!(monthly_price_cents: 2400)

    log = Billing::PlanSync.new.run!

    current = stripe.prices.select { _1[:lookup_key] == "shadetree_starter_monthly" }.sole
    assert_equal 2400, current[:unit_amount]
    assert_not old[:active]
    assert_includes log, "shadetree_starter_monthly: new price (the old one is archived)"
    assert_equal current[:id], Billing.price_id(plans(:starter), "monthly")
  end

  test "a plan made free has its product archived, and a dropped yearly price is archived" do
    Billing::PlanSync.new.run!
    plans(:starter).update!(annual_price_cents: 0)
    plans(:business).update!(monthly_price_cents: 0, annual_price_cents: 0, default: false)

    log = Billing::PlanSync.new.run!

    assert_empty stripe.prices.select { _1[:lookup_key] == "shadetree_starter_yearly" }
    assert_includes log, "shadetree_starter_yearly: archived (no yearly price)"
    assert_not stripe.products["shadetree_business"][:active]
  end

  test "lookup keys name the plan and interval" do
    assert_equal "shadetree_starter_yearly", plans(:starter).lookup_key("yearly")
    assert_equal [ plans(:starter), "yearly" ], Plan.for_lookup_key("shadetree_starter_yearly")
    assert_nil Plan.for_lookup_key("shadetree_nope_monthly")
    assert_nil Plan.for_lookup_key("other_starter_monthly")
    assert_raises(KeyError) { plans(:starter).lookup_key("weekly") }
  end
end
