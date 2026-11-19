# CAT-07: Settings → Locations. The tab appears once a business has a second location; the first
# one is added from the Business tab (only on plans with the "locations" feature, BIL-01). The
# main location's details are the business profile's, so its form only names it. Each location
# lists who works there; each member's default location is where their new documents start.
class Admin::LocationsController < Admin::BaseController
  impersonation :allowed
  requires_permission :business_settings
  before_action :set_location, only: %i[edit update archive restore]

  def index
    return redirect_to(edit_admin_business_path) unless current_business.multiple_locations?

    locations = Location.ordered.includes(:members).to_a
    @locations, @archived = locations.partition { !_1.archived? }
    @members = current_business.business_users.active.includes(:user, :default_location).sort_by { _1.user.full_name.downcase }
    @working = @members.map(&:user_id).to_set # deactivated members aren't listed as working anywhere
  end

  def new
    return redirect_to(edit_admin_business_path, alert: Location.plan_message) unless current_business.entitlements.feature?(:locations)

    @location = Location.new
    @location.valid? # fills country, time zone and hours from the business
    @location.errors.clear
  end

  def create
    @location = Location.new(location_params)
    if save_with_members
      redirect_to admin_locations_path, notice: "#{@location.name} added. Set its hours on the Hours tab."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    @location.assign_attributes(@location.primary? ? location_params.slice(:name) : location_params)
    if save_with_members
      redirect_to admin_locations_path, notice: "#{@location.name} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    @location.archive!
    redirect_to admin_locations_path, notice: "#{@location.name} archived. Its quotes, jobs and invoices stay as they are."
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_locations_path, alert: @location.errors.full_messages.to_sentence
  end

  def restore
    @location.restore!
    redirect_to admin_locations_path, notice: "#{@location.name} restored."
  rescue ArgumentError => error
    redirect_to admin_locations_path, alert: error.message
  end

  # A member's default location, from the team list on the index.
  def default_for
    member = current_business.business_users.find_by!(uid: params[:member].to_s)
    location = Location.active.find_by(uid: params[:default_location].to_s)
    member.update!(default_location: location)
    redirect_to admin_locations_path, notice: "New documents from #{member.user.full_name} start at #{(location || current_business.primary_location).name}."
  end

  private

  def set_location = @location = Location.find_by_param!(params[:id])

  def location_params
    permitted = params.require(:location).permit(:name, :address_line1, :address_line2, :city, :region, :postal_code, :country, :phone, :email, :timezone)
    # CAT-08: its own default taxes (ticked rates, maybe none), or the business's (nil).
    if params[:location].key?(:own_tax_rates)
      own = params[:location][:own_tax_rates] == "1"
      permitted[:tax_rate_ids] = own ? TaxRate.active.where(uid: Array(params[:location][:tax_rate_ids])).pluck(:id) : nil
    end
    permitted
  end

  # The members ticked on the form, if it was sent with the team list (only active members).
  def save_with_members
    Location.transaction do
      @location.save || raise(ActiveRecord::Rollback)
      if params[:location]&.key?(:member_ids)
        wanted = current_business.business_users.active.where(uid: Array(params[:location][:member_ids])).pluck(:user_id)
        @location.location_members.where.not(user_id: wanted).delete_all
        (wanted - @location.location_members.pluck(:user_id)).each { @location.location_members.create!(user_id: _1) }
      end
      true
    end
  end
end
