class Admin::BusinessesController < Admin::BaseController
  skip_before_action :require_business_setup, only: [:new, :create]
  layout "business_setup", only: [:new]
  layout "admin", only: [:edit, :update]

  def new
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

    if @business.update(business_params)
      redirect_to edit_admin_business_path, notice: "Business updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def business_params
    params.require(:business).permit(:name, :industry, :email, :phone, :address, :description, :website)
  end
end

