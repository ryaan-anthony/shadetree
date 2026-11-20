# OPS-04: release flags (PLT-11) without the console: off, on for everyone, a percentage of
# businesses, or a list of businesses (by their IDs). Only flags declared in config are shown.
# Audited, with the operator as the flag's changed_by.
class Ops::FeatureFlagsController < Ops::BaseController
  before_action :require_recent_verification, only: :update

  def index
    @flags = Feature.status
  end

  def update
    name = params[:id].to_s
    return redirect_to(ops_feature_flags_path, alert: "There's no flag called #{name}.") unless Feature.defined?(name)

    by = current_user.email
    before = flag_state(name)
    case params[:state]
    when "on" then Feature.enable!(name, by:)
    when "off" then Feature.disable!(name, by:)
    when "percentage" then Feature.enable_percentage!(name, params[:percentage].to_i.clamp(0, 100), by:)
    when "businesses"
      uids = params[:businesses].to_s.split(/[\s,]+/).compact_blank.uniq
      businesses = Business.where(uid: uids).to_a
      return redirect_to(ops_feature_flags_path, alert: "Unknown business IDs: #{(uids - businesses.map(&:uid)).join(", ")}") if businesses.size != uids.size

      # One change: never off for everyone in between. An empty list is off.
      FeatureFlag.transaction do
        Feature.disable!(name, by:)
        businesses.each { Feature.enable_for!(name, _1, by:) }
      end
    else return redirect_to(ops_feature_flags_path, alert: "Pick a setting.")
    end
    audit!("feature_flag.changed", flag: name, from: before, to: flag_state(name))
    redirect_to ops_feature_flags_path, notice: "#{name} updated."
  end

  private

  def flag_state(name)
    flag = FeatureFlag.find_by(name:) || FeatureFlag.new(name:)
    { "state" => flag.state, "percentage" => flag.percentage, "businesses" => Business.where(id: flag.business_ids).pluck(:uid).sort }
  end
end
