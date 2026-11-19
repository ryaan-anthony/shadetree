# OPS-02: the business directory and each business's page. Opening a business is audited.
class Ops::BusinessesController < Ops::BaseController
  PER_PAGE = 25

  def index
    @directory = Ops::Directory.new(params)
    scope = @directory.businesses
    @total = scope.unscope(:select, :order, :includes).count
    @page = params[:page].to_i.clamp(1, [ (@total.to_f / PER_PAGE).ceil, 1 ].max)
    @businesses = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @plans = Plan.order(:position, :id)
  end

  def show
    @business = Business.find_by!(uid: params[:id].to_s)
    @summary = Ops::BusinessSummary.new(@business)
    audit!("business.viewed", business: @business)
  end
end
