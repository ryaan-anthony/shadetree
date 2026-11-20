# OPS-04: editing industry presets (CAT-05): each industry's default visit length and starter
# services. Edits survive deploys (presets:sync only adds missing industries). Audited.
class Ops::PresetsController < Ops::BaseController
  BLANK_ROWS = 3

  before_action :set_preset, only: %i[edit update]

  def index
    @presets = IndustryPreset.all.sort_by(&:name)
  end

  def edit; end

  def update
    fields = %i[name description unit custom_unit taxable duration_minutes category]
    submitted = params.fetch(:items, {})
    rows = submitted.permit(submitted.keys.index_with { fields }).to_h.sort_by { |index, _| index.to_i }.map(&:last)
    items = rows.filter_map do |row|
      next if row["name"].to_s.strip.empty?

      { "name" => row["name"].to_s.strip, "description" => row["description"].to_s.strip.presence, "unit" => row["unit"].presence || "each",
        "custom_unit" => row["custom_unit"].to_s.strip.presence, "taxable" => row["taxable"] == "1",
        "duration_minutes" => minutes(row["duration_minutes"]),
        "category" => row["category"].to_s.strip.presence }.compact
    end
    @preset.assign_attributes(default_visit_minutes: params[:default_visit_minutes].to_i, items:)
    changes = @preset.changes_to_save.slice("default_visit_minutes", "items").transform_values { |from, to| { "from" => from, "to" => to } }
    if @preset.save
      audit!("preset.updated", industry: @preset.industry, items: items.size, changes:) # from and to, so a bad edit can be put back
      redirect_to ops_presets_path, notice: "#{@preset.name} saved. New businesses in it get these services."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_preset = @preset = IndustryPreset.find(params[:id])

  # Blank is no duration; anything but a whole number fails the preset's check.
  def minutes(value)
    value = value.to_s.strip
    value.empty? ? nil : (Integer(value, 10, exception: false) || -1)
  end
end
