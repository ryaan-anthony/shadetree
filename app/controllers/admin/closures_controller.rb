# Closures (CAT-06): holidays, vacation and part-days, listed on the hours tab.
class Admin::ClosuresController < Admin::BaseController
  requires_permission :business_settings
  before_action :set_closure, only: %i[edit update destroy]

  def new
    @closure = Closure.new(starts_on: current_business.today)
  end

  def create
    @closure = Closure.new(closure_params)
    if @closure.save
      redirect_to admin_hours_path, notice: "#{@closure.reason} added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @closure.update(closure_params)
      redirect_to admin_hours_path, notice: "#{@closure.reason} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @closure.destroy!
    redirect_to admin_hours_path, notice: "#{@closure.reason} removed."
  end

  private

  def set_closure = @closure = Closure.find_by_param!(params[:id])

  def closure_params = params.require(:closure).permit(:reason, :starts_on, :ends_on, :part_of_day, :start_time, :end_time, :repeats_yearly)
end
