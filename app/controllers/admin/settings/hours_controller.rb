class Admin::Settings::HoursController < Admin::BaseController
  def edit
    @business = current_user.current_business
  end

  def update
    @business = current_user.current_business

    if @business.update(hours_params)
      redirect_to edit_admin_settings_hours_path, notice: "Hours updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

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
end
