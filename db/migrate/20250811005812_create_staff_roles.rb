class CreateStaffRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_roles do |t|
      # Join table relationships
      t.references :staff_member, null: false, foreign_key: true
      t.references :business_role, null: false, foreign_key: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :staff_roles, [ :staff_member_id, :business_role_id ], unique: true, name: 'index_staff_roles_on_staff_member_and_role'
  end
end
