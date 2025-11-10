class Admin::BusinessesController < Admin::BaseController
  skip_before_action :require_business_setup, only: [ :new, :create ]

  layout :determine_layout

  def new
    # Allow creating additional businesses
    @business = current_user.owned_businesses.build
  end

  def create
    @business = current_user.owned_businesses.build(business_params)
    @business.owner = current_user

    if @business.save
      redirect_to admin_root_path, notice: "Business created successfully!"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @business = current_user.current_business
    redirect_to admin_root_path, alert: "Please create a business first." unless @business
  end

  def update
    @business = current_user.current_business
    unless @business
      redirect_to admin_root_path, alert: "Please create a business first."
      return
    end

    # Determine which params to use based on tab
    update_params = case params[:tab]
    when "hours"
      hours_params
    when "branding"
      branding_params
    else
      business_params
    end

    if @business.update(update_params)
      redirect_to edit_admin_business_path(tab: params[:tab]), notice: "#{params[:tab]&.capitalize || 'Business'} updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def switch
    Rails.logger.info "Business switch requested by user #{current_user.id} for business_id: #{params[:business_id]}"

    business = current_user.businesses.find_by(id: params[:business_id])

    if business
      session[:current_business_id] = business.id
      Rails.logger.info "Successfully switched to business #{business.id} (#{business.name})"
      render json: { success: true, business: { id: business.id, name: business.name } }
    else
      Rails.logger.warn "Business switch failed - business not found or not accessible. User businesses: #{current_user.businesses.pluck(:id).inspect}"
      render json: { success: false, error: "Business not found" }, status: :not_found
    end
  end

  private

  def business_params
    params.require(:business).permit(:name, :industry, :email, :phone, :address, :description, :website)
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

    # Only return timezone for now
    { timezone: permitted[:timezone] }
  end

  def branding_params
    params.require(:business).permit(:logo_url, :brand_color)
  end

  def determine_layout
    action_name == "new" ? "business_setup" : "admin"
  end
end
