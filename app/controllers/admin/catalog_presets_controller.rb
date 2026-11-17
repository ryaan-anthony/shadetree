# Add an industry's starter services to the catalog (CAT-05).
class Admin::CatalogPresetsController < Admin::BaseController
  requires_permission :business_settings

  def show
    @industry = params[:industry].presence_in(Industry.keys) || current_business.industry
    @preset = IndustryPreset.for(@industry)
    @presets = IndustryPreset.where(industry: Industry.keys).sort_by { Industry.keys.index(_1.industry) }
  end

  def create
    preset = IndustryPreset.find_by!(industry: params[:industry].to_s.presence_in(Industry.keys))
    names = Array(params[:names]).compact_blank
    if names.empty?
      return redirect_to admin_catalog_presets_path(industry: preset.industry), alert: "Pick at least one service to add."
    end

    added = preset.add_to_catalog!(names)
    message = added.any? ? "Added #{helpers.pluralize(added.size, "service")} to your catalog. Set your prices next." : "Nothing new to add: those services are already in your catalog."
    redirect_after_setup_step admin_catalog_items_path, notice: message
  end
end
