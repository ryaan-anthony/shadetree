# MKT-01: words for the public site, worked out from the plans (BIL-01) so they can't drift from
# what the app enforces.
module MarketingHelper
  # Plan features that a plan can list before the feature itself ships: shown as "coming soon"
  # rather than promised. Remove a key here when its spec merges (ACC-07, SMS).
  COMING_SOON = %w[custom_roles sms].freeze

  # "5 quotes a month", "Unlimited quotes".
  def plan_quota(plan)
    quotes = plan.limits["quotes_sent"]
    quotes.nil? ? "Unlimited quotes" : "#{number_with_delimiter(quotes)} #{"quote".pluralize(quotes)} a month"
  end

  # "2 team members", "Unlimited team members".
  def plan_team(plan)
    members = plan.limits["team_members"]
    members.nil? ? "Unlimited team members" : "#{members} team #{"member".pluralize(members)}"
  end

  # Whole dollars when there are no cents: "$19", "$0".
  def plan_price(money) = money.format.delete_suffix(".00")

  # What a year costs per month, to the cent below: "$15.83".
  def plan_annual_monthly(plan) = plan_price(Money.new(plan.annual_price_cents / 12, plan.currency))

  # How many months a year's price saves against paying monthly ("2 months free"), or nil.
  def plan_annual_saving(plan)
    return unless plan_yearly?(plan)

    months = ((plan.monthly_price_cents * 12) - plan.annual_price_cents) / plan.monthly_price_cents
    "#{months} #{"month".pluralize(months)} free" if months.positive?
  end

  # Whether a paid plan has a yearly price to show (0 means it has no yearly option).
  def plan_yearly?(plan) = !plan.free? && plan.monthly_price_cents.positive? && plan.annual_price_cents.positive?

  # The features this plan adds over the one before it, as [label, coming_soon?].
  def plan_new_features(plan, previous)
    keys = Plan::FEATURES.keys.select { plan.features[_1] && !(previous&.features&.dig(_1)) }
    keys.map { [ Plan::FEATURES[_1], COMING_SOON.include?(_1) ] }
  end
end
