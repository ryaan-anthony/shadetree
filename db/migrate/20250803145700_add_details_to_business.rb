class AddDetailsToBusiness < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :description, :text
    add_column :businesses, :website, :string
    add_column :businesses, :industry, :string
    add_column :businesses, :logo_url, :string
    add_column :businesses, :brand_color, :string
    add_column :businesses, :service_area_radius, :decimal
    add_column :businesses, :latitude, :decimal
    add_column :businesses, :longitude, :decimal
    add_column :businesses, :tax_id, :string
    add_column :businesses, :license_number, :string
    add_column :businesses, :insurance_provider, :string
    add_column :businesses, :insurance_policy_number, :string
    add_column :businesses, :business_hours, :json
    add_column :businesses, :service_areas, :json
    add_column :businesses, :onboarding_completed, :boolean, default: false
  end
end
