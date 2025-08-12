class CreateStaffMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_members do |t|
      # Business and user relationships
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Staff member configuration
      t.string :status, default: 'active'

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :staff_members, :status
    add_index :staff_members, [:business_id, :user_id], unique: true, name: 'index_staff_members_on_business_and_user'
  end
end
