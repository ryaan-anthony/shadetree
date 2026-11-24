# ACC-09: a member's profile in each business they belong to (the photo is an attachment), and
# the history of changes someone else made to it.
class AddTeamProfiles < ActiveRecord::Migration[8.1]
  def change
    change_table :business_users, bulk: true do |t|
      t.string :title
      t.text :bio
      t.string :work_phone
    end
    add_check_constraint :business_users, "char_length(title) <= 40", name: "business_users_title_length"
    add_check_constraint :business_users, "char_length(bio) <= 200", name: "business_users_bio_length"

    create_table :profile_events do |t|
      t.references :business, null: false, foreign_key: true
      t.references :business_user, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify } # who changed it
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
    end
  end
end
