# ACC-07: custom roles, each a named set of permissions from the catalog (Permissions), and the
# record of changes to them. A member or invitation with a custom role has role "custom" and
# its role_id.
class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :name, null: false
      t.string :permissions, array: true, null: false, default: []
      t.timestamps
    end
    add_index :roles, :uid, unique: true
    add_index :roles, "business_id, lower(name)", unique: true, name: "index_roles_on_business_and_name"

    create_table :role_events do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :role, foreign_key: { on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
    end

    add_reference :business_users, :role, foreign_key: true
    add_reference :invitations, :role, foreign_key: true
    add_check_constraint :business_users, "(role = 'custom') = (role_id IS NOT NULL)", name: "business_users_custom_role"
  end
end
