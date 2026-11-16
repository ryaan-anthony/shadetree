class Admin::BusinessesController < Admin::BaseController
  skip_before_action :require_business_setup, only: [ :new, :create ]
  allow_without_business only: %i[new create]
  allow_any_member only: :switch
  requires_permission :business_settings, only: %i[edit update]

  # First business after sign-up, or another one from the switcher. Only name and industry.
  def new
    @business = current_user.owned_businesses.build
  end

  def create
    @business = current_user.owned_businesses.build(params.require(:business).permit(:name, :industry, :timezone))
    @business.owner = current_user
    @business.timezone = nil unless ActiveSupport::TimeZone[@business.timezone.to_s] # browser guess only

    if @business.save(context: :setup)
      switch_business_to(@business)
      redirect_to admin_root_path, notice: "#{@business.name} is ready."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @business = current_business
  end

  def update
    @business = current_business
    @tab = params[:tab].presence_in(SETTINGS_TABS) || "business"
    attributes = @tab == "branding" ? branding_params : settings_params

    if @business.update(attributes)
      redirect_after_setup_step edit_admin_business_path(tab: (@tab unless @tab == "business")), notice: "Settings saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

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

  SETTINGS_TABS = %w[business documents branding].freeze

  # Business and Documents tabs share one form model; each only sends its own fields.
  def settings_params
    params.require(:business).permit(
      :name, :industry, :description, :email, :phone, :website,
      :address_line1, :address_line2, :city, :region, :postal_code, :country, :timezone, :currency,
      :quote_expiry_days, :quote_terms, :quote_approved_message, :invoice_due_days, :invoice_terms, :quote_number_prefix, :invoice_number_prefix
    )
  end

  def branding_params
    params.require(:business).permit(:logo, :remove_logo, :brand_color)
  end
end
