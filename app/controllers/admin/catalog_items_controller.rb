# The service catalog: what a business sells, with default prices (CAT-03).
class Admin::CatalogItemsController < Admin::BaseController
  requires_permission :business_settings
  requires_permission :office, only: :search # the picker on quotes, invoices and jobs
  SEARCH_LIMIT = 50
  RECENT_LIMIT = 5

  before_action :set_item, only: %i[edit update archive restore move]
  leaves_session_alone only: :search

  def index
    @query = params[:q].to_s.strip
    @showing_archived = params[:archived] == "1"
    scope = @showing_archived ? CatalogItem.archived : CatalogItem.active
    @items = scope.search(@query).includes(:category).ordered
    @groups = @items.group_by(&:category).sort_by { |category, _| category ? [ 0, category.position, category.name ] : [ 1 ] }
    @archived_count = CatalogItem.archived.count
    # CAT-08: each item's prices at other locations (active ones, with several locations).
    @overrides = if current_business.multiple_locations?
      LocationPrice.joins(:location).merge(Location.active).where(catalog_item: @items).includes(:location, :business)
                   .group_by(&:catalog_item_id).transform_values { |prices| prices.sort_by { _1.location.name.downcase } }
    else
      {}
    end
  end

  # ?duplicate_of=<uid> starts from an unsaved copy of that item; ?category=<uid> preselects one.
  def new
    @item =
      if params[:duplicate_of].present?
        CatalogItem.find_by_param!(params[:duplicate_of]).duplicate
      else
        CatalogItem.new(category_id: CatalogCategory.find_by(uid: params[:category])&.id)
      end
  end

  def create
    @item = CatalogItem.new(item_params)
    assign_new_category
    if @item.save
      redirect_to admin_catalog_items_path(anchor: "item-#{@item.uid}"), notice: "#{@item.name} added to your catalog."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    @item.assign_attributes(item_params)
    assign_new_category
    if @item.save
      redirect_to admin_catalog_items_path(anchor: "item-#{@item.uid}"), notice: "#{@item.name} saved. Existing quotes and invoices keep their prices."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    @item.archive!
    redirect_to admin_catalog_items_path, notice: "#{@item.name} archived. It's hidden from pickers; existing documents are unchanged."
  end

  def restore
    @item.restore!
    redirect_to admin_catalog_items_path, notice: "#{@item.name} restored."
  end

  def move
    @item.move!(params[:direction].to_i)
    redirect_to admin_catalog_items_path(anchor: "item-#{@item.uid}")
  end

  # JSON for the item picker: active items matching ?q=, or the picker's recent ?uids= in
  # the order given (archived ones drop out).
  def search
    scope = CatalogItem.active.includes(:category)
    items =
      if params[:uids].present?
        uids = params[:uids].to_s.split(",").first(RECENT_LIMIT)
        scope.where(uid: uids).sort_by { uids.index(_1.uid) }
      else
        scope.search(params[:q]).order(:name).limit(SEARCH_LIMIT)
      end
    # CAT-08: priced for the document's location when the builder says which.
    location = Location.find_by(uid: params[:location].to_s) if params[:location].present?
    overrides = LocationPrice.cents_at(location, items)
    render json: { items: items.map { _1.as_picker_json(location:, overrides:) } }
  end

  private

  def set_item = @item = CatalogItem.find_by_param!(params[:id])

  def item_params
    params.require(:catalog_item).permit(:name, :description, :unit, :custom_unit, :unit_price, :taxable,
                                         :duration_minutes, :show_on_request_form, :category_id, location_price_inputs: {}).tap do |permitted|
      # Categories arrive as uids from the form.
      if permitted.key?(:category_id)
        permitted[:category_id] = CatalogCategory.find_by(uid: permitted[:category_id].to_s)&.id
      end
    end
  end

  def assign_new_category
    name = params.dig(:catalog_item, :new_category_name).to_s.squish
    return if name.blank?

    @item.category = CatalogCategory.where("lower(name) = ?", name.downcase).first || CatalogCategory.new(name:)
  end
end
