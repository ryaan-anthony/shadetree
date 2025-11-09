class Admin::BusinessOnboardingController < Admin::BaseController
  STEPS = %w[basics hours location branding complete].freeze

  before_action :set_business
  before_action :validate_step, only: [:new, :create]
  before_action :authorize_business, only: [:create]

  def new
    @step = params[:step] || "basics"

    # Set current onboarding step if not set
    @business.update(onboarding_step: @step) if @business.persisted? && @business.onboarding_step.blank?
  end

  def create
    @step = params[:step] || "basics"

    if update_business_for_step(@step)
      @business.update(onboarding_step: @step)

      next_step = get_next_step(@step)
      if next_step == "complete"
        complete_onboarding
      else
        redirect_to new_admin_business_onboarding_path(step: next_step),
                    notice: "#{@step.capitalize} information saved successfully."
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_business
    @business = if current_user.has_business?
      current_user.owned_businesses.first || current_user.businesses.first
    else
      current_user.owned_businesses.build(owner: current_user)
    end
  end

  def authorize_business
    # Ensure user owns the business they're trying to onboard
    if @business.persisted? && @business.owner_id != current_user.id
      redirect_to admin_root_path, alert: "Unauthorized access."
      return false
    end
  end

  def validate_step
    @step = params[:step] || "basics"
    unless STEPS.include?(@step) || @step == "complete"
      redirect_to new_admin_business_onboarding_path(step: "basics"),
                  alert: "Invalid onboarding step."
    end
  end

  def update_business_for_step(step)
    case step
    when "basics"
      @business.assign_attributes(basics_params)
    when "hours"
      @business.assign_attributes(hours_params)
    when "location"
      @business.assign_attributes(location_params)
    when "branding"
      @business.assign_attributes(branding_params)
    end

    @business.save
  end

  def get_next_step(current_step)
    current_index = STEPS.index(current_step)
    return "complete" if current_index.nil? || current_index >= STEPS.length - 2

    STEPS[current_index + 1]
  end

  def complete_onboarding
    if @business.complete_onboarding!
      redirect_to admin_root_path,
                  notice: "Welcome to Shadetree! Your business profile has been set up successfully."
    else
      redirect_to new_admin_business_onboarding_path(step: "basics"),
                  alert: "Unable to complete onboarding. Please try again."
    end
  end

  def basics_params
    params.require(:business).permit(:name, :email, :phone, :address, :description, :website, :industry)
  end

  def hours_params
    permitted = params.permit(
      :timezone,
      :monday_enabled, :monday_start, :monday_end,
      :tuesday_enabled, :tuesday_start, :tuesday_end,
      :wednesday_enabled, :wednesday_start, :wednesday_end,
      :thursday_enabled, :thursday_start, :thursday_end,
      :friday_enabled, :friday_start, :friday_end,
      :saturday_enabled, :saturday_start, :saturday_end,
      :sunday_enabled, :sunday_start, :sunday_end
    )

    # Only return timezone for now - we'll store hours in a separate model later
    { timezone: permitted[:timezone] }
  end

  def location_params
    # Location/service area will be implemented later with Location model
    # For now, just allow this step to pass through
    {}
  end

  def branding_params
    params.require(:business).permit(:logo_url, :brand_color)
  end
end
