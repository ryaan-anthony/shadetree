# Business hours and closures (CAT-06), a tab of business settings.
class Admin::HoursController < Admin::BaseController
  requires_permission :business_settings

  def show
    @business = current_business
    load_closures
  end

  # The weekly hours from the form, or the "weekdays 8–5" preset.
  def update
    @business = current_business
    return redirect_to(admin_hours_path, alert: "That preset isn't available.") if params.key?(:preset) && params[:preset] != "weekdays"

    @business.weekly_hours = params[:preset] == "weekdays" ? WeeklyHours::WEEKDAYS_8_TO_5 : WeeklyHours.from_form(hours_params)
    if @business.save
      redirect_to admin_hours_path, notice: params[:preset] == "weekdays" ? "Hours set to weekdays, 8 am to 5 pm." : "Hours saved."
    else
      load_closures
      render :show, status: :unprocessable_content
    end
  end

  private

  def hours_params = params.fetch(:hours, {}).permit(WeeklyHours::DAYS.to_h { [ _1.to_s, %i[open opens closes] ] })

  # Upcoming and yearly closures by when they next happen; past ones are kept, but listed apart.
  def load_closures
    today = @business.today
    closures = Closure.ordered.to_a.each { _1.association(:business).target = @business }
    @closures, @past_closures = closures.partition { _1.current?(today) }
    @closures = @closures.sort_by { [ _1.next_on(today), _1.id ] }
    @past_closures = @past_closures.sort_by(&:ends_on).reverse.first(20)
  end
end
