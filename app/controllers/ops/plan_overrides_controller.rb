# OPS-04: comping limits or features for one business (BIL-01's per-business overrides), with a
# reason. Entitlements apply them at once; nothing is billed or changed in the billing provider.
class Ops::PlanOverridesController < Ops::BaseController
  before_action :require_recent_verification, only: :update
  before_action { @business = Business.find_by!(uid: params[:business_id].to_s) }

  def edit; end

  def update
    return redirect_to(edit_ops_business_plan_overrides_path(@business), alert: "Give a reason for the change.") if reason.blank?

    limits = Plan::LIMITS.keys.each_with_object({}) do |key, chosen|
      case params.dig(:limits, key, :mode)
      when "unlimited" then chosen[key] = nil
      when "custom" then chosen[key] = Integer(params.dig(:limits, key, :value).to_s, 10, exception: false) || -1
      end
    end
    features = Plan::FEATURES.keys.each_with_object({}) do |key, chosen|
      mode = params.dig(:features, key)
      chosen[key] = mode == "on" if %w[on off].include?(mode)
    end
    overrides = { "limits" => limits, "features" => features }.compact_blank
    previous = @business.plan_overrides
    if @business.update(plan_overrides: overrides)
      audit!("business.plan_overrides_changed", business: @business, reason:, from: previous, to: overrides)
      redirect_to ops_business_path(@business, anchor: "plan"), notice: overrides.empty? ? "#{@business.name} is back to its plan's limits and features." : "Overrides saved for #{@business.name}."
    else
      flash.now[:alert] = @business.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  def reason = params[:reason].to_s.strip.first(500)
end
