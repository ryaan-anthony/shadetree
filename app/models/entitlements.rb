# What a business's plan allows (BIL-01 wires these to plans). Until billing exists, every
# business gets the free plan's answers.
class Entitlements
  def self.for(business) = new(business)

  def initialize(business)
    @business = business
  end

  # Hiding "Powered by Shadetree" on client pages is a paid feature.
  def remove_powered_by? = false
end
