class CreateBusinesses < ActiveRecord::Migration[8.0]
  def change
    create_table :businesses do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.text :address
      t.string :city
      t.string :state
      t.string :zip_code
      t.string :industry
      t.text :description
      t.string :website
      t.string :brand_color, default: '#059669'
      t.decimal :service_area_radius, precision: 8, scale: 2
      t.boolean :active, default: true
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :businesses, :email, unique: true
    add_index :businesses, :owner_id
  end
end
