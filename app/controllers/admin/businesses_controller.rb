class Admin::BusinessesController < Admin::BaseController
  skip_before_action :require_business_setup, only: [ :new, :create ]

  def new
    # Allow creating additional businesses
    @business = current_user.owned_businesses.build
  end

  def create
    @business = current_user.owned_businesses.build(business_params)
    @business.owner = current_user

    if @business.save
      switch_business_to(@business)
      redirect_to admin_root_path, notice: "Business created successfully!"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @business = current_business
  end

  def update
    @business = current_business

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

  # Switch the current business. Only active memberships count; anything else is "not found"
  # (ADR 0014). Businesses are identified by their opaque uid, never the sequential id.
  def switch
    membership = current_user.business_users.active.joins(:business).find_by(businesses: { uid: params[:business].to_s })

    if membership
      switch_business_to(membership.business)
      respond_to do |format|
        format.html { redirect_to admin_root_path, notice: "Switched to #{membership.business.name}." }
        format.json { render json: { success: true, business: { id: membership.business.uid, name: membership.business.name } } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_root_path, alert: "That business isn't available to you." }
        format.json { render json: { success: false, error: "Business not found" }, status: :not_found }
      end
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
end
