# CAT-02: logos are uploaded (Active Storage), not linked. The old logo_url pointed at images
# hosted elsewhere, which we can't import safely, so owners upload their logo again; the
# dashboard checklist asks them to.
class ReplaceLogoUrlWithUpload < ActiveRecord::Migration[8.1]
  def change
    remove_column :businesses, :logo_url, :string
    # The old default (#059669) is too light for white button text (3.8:1); Forest reads at 5.5:1.
    change_column_default :businesses, :brand_color, from: "#059669", to: "#047857"
  end
end
