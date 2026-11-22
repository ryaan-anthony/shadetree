# #289: examples in placeholders that fit the business's trade (from its industry's starter
# services, CAT-05), so a pest-control business isn't shown lawn-mowing copy. Without an
# industry they stay neutral.
#
#   example_service           # => "General pest treatment" (pest control), "Service call" (none)
#   example_title             # => "e.g. General pest treatment"
module ExamplesHelper
  NEUTRAL_SERVICE = "Service call".freeze

  def example_service(business = current_business)
    @example_service ||= {}
    @example_service[business&.id] ||= (business&.industry.presence && IndustryPreset.for(business.industry)&.item_list&.first&.name) || NEUTRAL_SERVICE
  end

  def example_title(business = current_business) = "e.g. #{example_service(business)}"

  # The note on a request logged from a call.
  def example_request_note(business = current_business)
    "e.g. Called about #{example_service(business).downcase}. Prefers mornings; use the side gate."
  end
end
