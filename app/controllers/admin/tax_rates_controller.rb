# Tax rates (CAT-04), a tab of business settings.
class Admin::TaxRatesController < Admin::BaseController
  requires_permission :business_settings
  before_action :set_rate, only: %i[edit update archive restore]

  def index
    @rates = TaxRate.active.ordered
    @archived = TaxRate.archived.order(archived_at: :desc)
  end

  def new
    @rate = TaxRate.new(applies_by_default: TaxRate.active.none? || TaxRate.default_set.any?)
  end

  def create
    @rate = TaxRate.new(rate_params)
    if @rate.save
      redirect_to admin_tax_rates_path, notice: "#{@rate.label} added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @rate.update(rate_params)
      redirect_to admin_tax_rates_path, notice: "#{@rate.label} saved. Existing quotes and invoices keep the rate they had."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    @rate.archive!
    redirect_to admin_tax_rates_path, notice: "#{@rate.label} archived. New documents won't use it; existing ones are unchanged."
  end

  def restore
    if @rate.update(archived_at: nil)
      redirect_to admin_tax_rates_path, notice: "#{@rate.label} restored."
    else
      redirect_to admin_tax_rates_path, alert: @rate.errors.full_messages.to_sentence
    end
  end

  private

  def set_rate = @rate = TaxRate.find_by_param!(params[:id])

  def rate_params = params.require(:tax_rate).permit(:name, :percent, :applies_by_default)
end
