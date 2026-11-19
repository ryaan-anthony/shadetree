# OPS-03: an event recorded while Shadetree support was viewing the app as a member notes it, so
# the record's history reads "Dana Whitaker via Shadetree support" rather than just the member.
module SupportAttribution
  extend ActiveSupport::Concern

  included do
    before_create { self.data = (data || {}).merge("via_support" => true) if Current.impersonator }
  end

  def via_support? = data.is_a?(Hash) && data["via_support"] == true

  # The person's name, as histories show it.
  def actor_label(fallback = nil)
    name = user&.full_name || fallback
    name && via_support? ? "#{name} via Shadetree support" : name
  end
end
