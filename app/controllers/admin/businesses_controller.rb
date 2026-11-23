class Admin::BusinessesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  impersonation :blocked, only: %i[new create switch] # another business, or a new one, in the member's name
  skip_before_action :require_business_setup, only: [ :new, :create ]
  allow_without_business only: %i[new create]
  allow_any_member only: :switch
  requires_permission :business_settings, only: %i[edit update request_form_qr]
  before_action :refuse_while_suspended, only: %i[new create]

  # First business after sign-up, or another one from the switcher. Only name and industry.
  def new
    @business = current_user.owned_businesses.build
  end

  def create
    @business = current_user.owned_businesses.build(params.require(:business).permit(:name, :industry, :timezone))
    @business.owner = current_user
    @business.timezone = nil unless ActiveSupport::TimeZone[@business.timezone.to_s] # browser guess only

    if Business.transaction { @business.save(context: %i[setup create]) }
      Analytics.track("Business Created", request:) # MKT-04
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
    return update_visit_emails if params[:tab] == "messages"
    return update_team_profiles if params[:tab] == "team_profiles" # ACC-09

    @tab = params[:tab].presence_in(SETTINGS_TABS) || "business"
    attributes = @tab == "branding" ? branding_params : settings_params
    # The search-engine choice only applies while requests are on; with them off it's ignored.
    attributes = attributes.except(:request_form_indexable) if attributes.key?(:request_form_indexable) && !ActiveModel::Type::Boolean.new.cast(attributes.fetch(:request_form_enabled, @business.request_form_enabled))

    if @business.update(attributes)
      redirect_after_setup_step edit_admin_business_path(tab: (@tab unless @tab == "business")), notice: "Settings saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # CLI-03: the request form link as a QR code, to print on flyers and trucks.
  def request_form_qr
    business = current_business
    png = RQRCode::QRCode.new(public_request_url(business.handle)).as_png(size: 600, border_modules: 2)
    send_data png.to_s, type: "image/png", filename: "#{business.handle}-request-form-qr.png", disposition: "attachment"
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

  # OPS-04: someone whose business is suspended can't start a fresh one to carry on (owner's
  # decision); they can still switch to another business they already belong to.
  def refuse_while_suspended
    @suspended_business = current_user.businesses.merge(BusinessUser.active).where.not(suspended_at: nil).first
    render "admin/businesses/suspended_new", status: :forbidden if @suspended_business
  end

  SETTINGS_TABS = %w[business documents branding request_form].freeze

  # Business and Documents tabs share one form model; each only sends its own fields.
  def settings_params
    params.require(:business).permit(
      :name, :industry, :description, :email, :phone, :website,
      :address_line1, :address_line2, :city, :region, :postal_code, :country, :timezone, :currency,
      :quote_expiry_days, :auto_create_jobs, :technicians_see_prices, :quote_terms, :quote_approved_message, :invoice_due_days, :invoice_terms, :quote_number_prefix, :invoice_number_prefix,
      :handle, :request_form_enabled, :request_form_intro, :request_form_indexable # CLI-03, MKT-04
    )
  end

  # JOB-05: the visit-email switches, on Settings → Messages (owner, 2026-11-22). Kinds not
  # given keep their setting.
  def update_visit_emails
    if @business.update(params.require(:business).permit(client_visit_emails: Business::CLIENT_VISIT_EMAILS.keys))
      redirect_to admin_message_templates_path, notice: "Visit emails saved."
    else # another of the business's settings needs fixing first; say which
      redirect_to admin_message_templates_path, alert: "Visit emails not saved: #{@business.errors.full_messages.to_sentence}"
    end
  end

  # ACC-09: "Show team profiles to clients", on Settings → Messages (owner, 2026-11-22).
  def update_team_profiles
    if @business.update(params.require(:business).permit(:show_team_profiles))
      redirect_to admin_message_templates_path(anchor: "team-profiles"), notice: @business.show_team_profiles? ? "Clients can now see who's coming." : "Team profiles are hidden from clients."
    else
      redirect_to admin_message_templates_path, alert: "Not saved: #{@business.errors.full_messages.to_sentence}"
    end
  end

  def branding_params
    params.require(:business).permit(:logo, :remove_logo, :brand_color)
  end
end
