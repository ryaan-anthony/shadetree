class Admin::BusinessOnboardingController < Admin::BaseController
  STEPS = %w[basics hours location branding complete].freeze

  def new
    @step = params[:step] || 'basics'
    @business = current_user.owned_businesses.build

    # Load existing business if user is editing
    if current_user.has_business?
      @business = current_user.current_business
    end
  end

  def create
    @step = params[:step] || 'basics'
    @business = find_or_initialize_business

    if update_business_for_step(@step)
      next_step = get_next_step(@step)
      if next_step == 'complete'
        complete_onboarding
      else
        redirect_to new_admin_business_onboarding_path(step: next_step)
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def find_or_initialize_business
    if current_user.has_business?
      current_user.current_business
    else
      current_user.owned_businesses.build(owner: current_user)
    end
  end

  def update_business_for_step(step)
    case step
    when 'basics'
      @business.assign_attributes(basics_params)
    when 'hours'
      @business.assign_attributes(hours_params)
    when 'location'
      @business.assign_attributes(location_params)
    when 'branding'
      @business.assign_attributes(branding_params)
    end

    @business.save
  end

  def get_next_step(current_step)
    current_index = STEPS.index(current_step)
    return 'complete' if current_index.nil? || current_index >= STEPS.length - 2

    STEPS[current_index + 1]
  end

  def complete_onboarding
    # The after_create callback on Business model already added owner to business_users
    # Just redirect to admin dashboard
    redirect_to admin_root_path, notice: 'Welcome to Shadetree! Your business profile has been set up successfully.'
  end

  def basics_params
    params.require(:business).permit(:name, :email, :phone, :address, :description, :website, :industry)
  end

  def hours_params
    # For now, we'll skip complex hours logic and just mark as completed
    {}
  end

  def location_params
    params.require(:business).permit(:service_area_radius, :latitude, :longitude)
  end

  def branding_params
    params.require(:business).permit(:logo_url, :brand_color)
  end
end
