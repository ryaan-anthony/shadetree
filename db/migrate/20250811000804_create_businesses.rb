class CreateBusinesses < ActiveRecord::Migration[8.0]
  def change
    create_table :businesses do |t|
      # Core business information
      t.string :name, null: false
      t.string :timezone
      t.string :email, null: false
      t.string :phone
      t.string :website

      # Business settings
      t.string :currency, default: 'USD'

      # Branding
      t.string :brand_color, default: '#059669'
      t.string :logo_url

      # Status
      t.boolean :active, default: true

      # Owner relationship
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :businesses, :email
    add_index :businesses, :active
  end
end
