class CreateBusinessUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :business_users do |t|
      t.references :user, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :role, default: 'member', null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :business_users, [ :user_id, :business_id ], unique: true
    add_index :business_users, [ :business_id, :active ]
    add_index :business_users, [ :user_id, :active ]
  end
end
