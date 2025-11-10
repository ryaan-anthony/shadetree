class Admin::Settings::BrandingController < Admin::BaseController
  def edit
    @business = current_user.current_business
  end

  def update
    @business = current_user.current_business

    if @business.update(branding_params)
      redirect_to edit_admin_settings_branding_path, notice: "Branding updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def branding_params
    params.require(:business).permit(:logo_url, :brand_color)
  end
end
