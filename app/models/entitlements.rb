# What a business's plan allows (BIL-01), with its per-business overrides (comped limits or
# features) on top. The one place the app asks "can this business do X?" and "how much of Y
# is left?", in views, actions, jobs and emails:
#
#   entitlements = Entitlements.for(business)
#   entitlements.feature?(:remove_powered_by)     # => false on Free
#   entitlements.limit(:team_members)             # => 2, or nil for unlimited
#   entitlements.remaining(:team_members)         # => 1, or nil for unlimited
#   entitlements.within?(:team_members, adding: 1)
#
# Cheap to call: the plan comes with the business, and usage is counted once per instance.
class Entitlements
  def self.for(business) = new(business)

  attr_reader :business

  def initialize(business)
    @business = business
    @usage = {}
  end

  def plan = business.plan

  def feature?(key)
    key = key.to_s
    raise ArgumentError, "Unknown feature #{key.inspect}" unless Plan::FEATURES.key?(key)

    overrides = business.plan_overrides.fetch("features", {})
    overrides.key?(key) ? overrides[key] == true : plan.features[key] == true
  end

  # The limit, or nil when it's unlimited.
  def limit(key)
    key = key.to_s
    raise ArgumentError, "Unknown limit #{key.inspect}" unless Plan::LIMITS.key?(key)

    overrides = business.plan_overrides.fetch("limits", {})
    overrides.key?(key) ? overrides[key] : plan.limits[key]
  end

  def unlimited?(key) = limit(key).nil?

  # How much is in use now (team members), or this period (quotes sent, from BIL-02).
  def used(key)
    @usage[key.to_s] ||= case key.to_s
    when "team_members" then Tenancy.with_business(business) { business.business_users.active.count + Invitation.pending.count }
    when "quotes_sent" then period.used("quote_sent")
    end
  end

  def remaining(key) = unlimited?(key) ? nil : [ limit(key) - used(key), 0 ].max

  # Whether `adding` more fits under the limit.
  def within?(key, adding: 1) = unlimited?(key) || used(key) + adding <= limit(key)

  def remove_powered_by? = feature?(:remove_powered_by)

  # The usage period (BIL-02): the calendar month on a free plan, the billing cycle on a paid one.
  def period = @period ||= UsagePeriod.for(business)

  # The team size message for invitations and reactivations (the owner counts, as do pending
  # invitations).
  def team_limit_message
    pending = Tenancy.with_business(business) { Invitation.pending.exists? }
    "Your #{plan.name} plan includes #{limit(:team_members)} people, counting you and pending invitations." \
      "#{" Revoke an invitation to make room, or see Settings → Plan." if pending}#{" See Settings → Plan." unless pending}"
  end
end
