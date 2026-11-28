# OPS-04: editing plans (BIL-01) without a deploy: name, description, whether it's listed,
# order, prices, limits and features. Which plan is the default, and its key, stay as seeded;
# the billing provider's prices are set up with subscriptions (BIL-04). Changes are audited.
class Ops::PlansController < Ops::BaseController
  before_action :require_recent_verification, only: :update
  before_action :set_plan, only: %i[edit update]

  def index
    @plans = Plan.order(:position, :id)
    # A business on a trial has the trial's plan but isn't paying for it, so trials are counted
    # on their own and left out of the plan's count.
    @counts = Business.where.not(billing_status: "trialing").group(:plan_id).count
    @trial_counts = Business.where(billing_status: "trialing").group(:plan_id).count
  end

  def edit; end

  def update
    attributes = params.require(:plan).permit(:name, :description, :public, :position, :platform_fee_bps)
    @plan.assign_attributes(attributes)
    @plan.monthly_price_cents = price_cents(params.dig(:plan, :monthly_price)) if params.dig(:plan, :monthly_price)
    @plan.annual_price_cents = price_cents(params.dig(:plan, :annual_price)) if params.dig(:plan, :annual_price)
    @plan.limits = Plan::LIMITS.keys.each_with_object({}) do |key, limits|
      value = params.dig(:plan, :limits, key).to_s.strip
      # Blank is unlimited; anything that isn't a whole number fails the plan's check, never
      # quietly becoming unlimited for every business on it.
      limits[key] = value.match?(/\A\d+\z/) ? value.to_i : value unless value.empty?
    end
    @plan.features = Plan::FEATURES.keys.index_with { params.dig(:plan, :features, _1) == "1" }.select { _2 }
    changes = @plan.changes_to_save.transform_values { |from, to| { "from" => from, "to" => to } }
    if @plan.save
      audit!("plan.updated", plan: @plan.key, changes:) if changes.any? # from and to, so a bad edit can be put back
      redirect_to ops_plans_path, notice: "#{@plan.name} saved. Every business on it has the new limits and features now."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_plan = @plan = Plan.find(params[:id])

  def price_cents(value)
    Money.parse(value.to_s.strip.presence || "0", @plan.currency).cents
  rescue ArgumentError
    -1 # not an amount: fails the plan's "0 or more" check
  end
end
