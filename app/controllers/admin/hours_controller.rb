# Business hours and closures (CAT-06), a tab of business settings. CAT-07: with more than one
# location, ?location=<uid> picks whose hours; the main location's are the business's.
class Admin::HoursController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :business_settings
  before_action :set_place

  def show = load_closures

  # The weekly hours from the form, or the "weekdays 8–5" preset.
  def update
    return redirect_to(hours_path, alert: "That preset isn't available.") if params.key?(:preset) && params[:preset] != "weekdays"

    @place.weekly_hours = params[:preset] == "weekdays" ? WeeklyHours::WEEKDAYS_8_TO_5 : WeeklyHours.from_form(hours_params)
    if @place.save
      redirect_to hours_path, notice: params[:preset] == "weekdays" ? "Hours set to weekdays, 8 am to 5 pm." : "Hours saved."
    else
      load_closures
      render :show, status: :unprocessable_content
    end
  end

  private

  # @place is what's edited: the business, or a location other than the main one (@location).
  def set_place
    @business = current_business
    @location = Location.where(primary: false).find_by_param!(params[:location]) if params[:location].present?
    @place = @location || @business
  end

  helper_method def hours_path = admin_hours_path(location: @location)

  def hours_params = params.fetch(:hours, {}).permit(WeeklyHours::DAYS.to_h { [ _1.to_s, %i[open opens closes] ] })

  # Upcoming and yearly closures by when they next happen; past ones are kept, but listed apart.
  def load_closures
    today = @place.is_a?(Location) ? @place.today : @business.today
    closures = Closure.where(location_id: @location&.id).ordered.to_a.each do |closure|
      closure.association(:business).target = @business
      closure.association(:location).target = @location
    end
    @closures, @past_closures = closures.partition { _1.current?(today) }
    @closures = @closures.sort_by { [ _1.next_on(today), _1.id ] }
    @past_closures = @past_closures.sort_by(&:ends_on).reverse.first(20)
  end
end
