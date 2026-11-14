# Baseline schema after the M0 reset (PLT-07). Replaces the 2025 migrations, which created
# tables for features that haven't been built. Each feature spec adds its own tables.
class CreateInitialSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Devise: database_authenticatable
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      # Devise: recoverable
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      # Devise: rememberable
      t.datetime :remember_created_at
      # Devise: confirmable
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email

      t.string :first_name
      t.string :last_name

      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token, unique: true

    # Profile fields stay close to the old shape; CAT-01 restructures the address.
    create_table :businesses do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :industry
      t.text :description
      t.text :address
      t.string :email
      t.string :phone
      t.string :website
      t.string :timezone
      t.string :currency, default: "USD"
      t.string :brand_color, default: "#059669"
      t.string :logo_url
      t.boolean :active, null: false, default: true
      t.string :onboarding_step
      t.datetime :onboarded_at

      t.timestamps
    end
    add_index :businesses, :active
    add_index :businesses, :industry

    # One membership per person per business. Roles: owner, admin, technician (ACC-04).
    create_table :business_users do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "technician"
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :business_users, [ :user_id, :business_id ], unique: true
    add_index :business_users, [ :business_id, :active ]
    add_index :business_users, [ :user_id, :active ]
  end
end
