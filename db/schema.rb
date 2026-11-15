# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_14_000700) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "business_users", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "technician", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_active_at"
    t.datetime "deactivated_at"
    t.string "uid", null: false
    t.index ["business_id", "active"], name: "index_business_users_on_business_id_and_active"
    t.index ["business_id"], name: "index_business_users_on_business_id"
    t.index ["uid"], name: "index_business_users_on_uid", unique: true
    t.index ["user_id", "active"], name: "index_business_users_on_user_id_and_active"
    t.index ["user_id", "business_id"], name: "index_business_users_on_user_id_and_business_id", unique: true
    t.index ["user_id"], name: "index_business_users_on_user_id"
  end

  create_table "businesses", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.string "name", null: false
    t.string "industry"
    t.text "description"
    t.text "address"
    t.string "email"
    t.string "phone"
    t.string "website"
    t.string "timezone"
    t.string "currency", default: "USD"
    t.string "brand_color", default: "#059669"
    t.string "logo_url"
    t.boolean "active", default: true, null: false
    t.string "onboarding_step"
    t.datetime "onboarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "uid", null: false
    t.index ["active"], name: "index_businesses_on_active"
    t.index ["industry"], name: "index_businesses_on_industry"
    t.index ["owner_id"], name: "index_businesses_on_owner_id"
    t.index ["uid"], name: "index_businesses_on_uid", unique: true
  end

  create_table "document_sequences", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "kind", null: false
    t.bigint "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "kind"], name: "index_document_sequences_on_business_id_and_kind", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "secret", null: false
    t.string "token_digest", null: false
    t.bigint "invited_by_id"
    t.bigint "accepted_by_id"
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at"
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "business_id, lower((email)::text)", name: "index_invitations_one_pending_per_email", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["accepted_by_id"], name: "index_invitations_on_accepted_by_id"
    t.index ["business_id"], name: "index_invitations_on_business_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.index ["uid"], name: "index_invitations_on_uid", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "terms_accepted_at"
    t.string "session_token"
    t.bigint "last_business_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_business_id"], name: "index_users_on_last_business_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "business_users", "businesses"
  add_foreign_key "business_users", "users"
  add_foreign_key "businesses", "users", column: "owner_id"
  add_foreign_key "document_sequences", "businesses"
  add_foreign_key "invitations", "businesses", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "accepted_by_id", on_delete: :nullify
  add_foreign_key "invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "users", "businesses", column: "last_business_id", on_delete: :nullify
end
