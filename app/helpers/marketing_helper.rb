# MKT-01: words for the public site, worked out from the plans (BIL-01) so they can't drift from
# what the app enforces.
module MarketingHelper
  # "5 quotes a month", "Unlimited quotes".
  def plan_quota(plan)
    quotes = plan.limits["quotes_sent"]
    quotes.nil? ? "Unlimited quotes" : "#{number_with_delimiter(quotes)} #{"quote".pluralize(quotes)} a month"
  end

  # Whole dollars when there are no cents: "$19", "$0".
  def plan_price(money) = money.format.delete_suffix(".00")
end
