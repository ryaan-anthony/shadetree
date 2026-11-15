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

ActiveRecord::Schema[8.1].define(version: 2026_11_15_000300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

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
    t.string "address_line1"
    t.string "address_line2"
    t.string "city"
    t.string "region"
    t.string "postal_code"
    t.string "country", default: "US", null: false
    t.integer "quote_expiry_days", default: 30, null: false
    t.text "quote_terms"
    t.integer "invoice_due_days", default: 14, null: false
    t.text "invoice_terms"
    t.string "quote_number_prefix", default: "Q", null: false
    t.string "invoice_number_prefix", default: "INV", null: false
    t.index ["active"], name: "index_businesses_on_active"
    t.index ["industry"], name: "index_businesses_on_industry"
    t.index ["owner_id"], name: "index_businesses_on_owner_id"
    t.index ["uid"], name: "index_businesses_on_uid", unique: true
  end

  create_table "catalog_categories", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "business_id, lower((name)::text)", name: "index_catalog_categories_unique_name", unique: true
    t.index ["business_id"], name: "index_catalog_categories_on_business_id"
    t.index ["uid"], name: "index_catalog_categories_on_uid", unique: true
  end

  create_table "catalog_items", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.bigint "category_id"
    t.string "name", null: false
    t.text "description"
    t.string "unit", default: "each", null: false
    t.string "custom_unit"
    t.integer "unit_price_cents"
    t.boolean "taxable", default: true, null: false
    t.integer "duration_minutes"
    t.boolean "show_on_request_form", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "archived_at", "position"], name: "idx_on_business_id_archived_at_position_80c3676433"
    t.index ["business_id"], name: "index_catalog_items_on_business_id"
    t.index ["category_id"], name: "index_catalog_items_on_category_id"
    t.index ["uid"], name: "index_catalog_items_on_uid", unique: true
  end

  create_table "client_contact_methods", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "client_id", null: false
    t.string "kind", null: false
    t.string "value", null: false
    t.string "normalized", null: false
    t.string "label"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "kind", "normalized"], name: "idx_on_business_id_kind_normalized_9d4b32aefd"
    t.index ["business_id"], name: "index_client_contact_methods_on_business_id"
    t.index ["client_id"], name: "index_client_contact_methods_on_client_id"
  end

  create_table "client_link_events", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "client_link_id", null: false
    t.string "kind", null: false
    t.string "device"
    t.datetime "occurred_at", null: false
    t.index ["business_id"], name: "index_client_link_events_on_business_id"
    t.index ["client_link_id", "kind"], name: "index_client_link_events_once", unique: true, where: "((kind)::text <> ALL (ARRAY[('view'::character varying)::text, ('fresh_link_requested'::character varying)::text]))"
    t.index ["client_link_id"], name: "index_client_link_events_on_client_link_id"
  end

  create_table "client_links", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "linkable_type", null: false
    t.bigint "linkable_id", null: false
    t.string "secret", null: false
    t.string "token_digest", null: false
    t.string "actions", default: [], null: false, array: true
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.bigint "revoked_by_id"
    t.bigint "created_by_id"
    t.datetime "first_viewed_at"
    t.datetime "last_viewed_at"
    t.integer "views_count", default: 0, null: false
    t.datetime "fresh_link_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_client_links_on_business_id"
    t.index ["created_by_id"], name: "index_client_links_on_created_by_id"
    t.index ["linkable_type", "linkable_id"], name: "index_client_links_on_linkable"
    t.index ["revoked_by_id"], name: "index_client_links_on_revoked_by_id"
    t.index ["token_digest"], name: "index_client_links_on_token_digest", unique: true
    t.index ["uid"], name: "index_client_links_on_uid", unique: true
  end

  create_table "clients", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "display_name", null: false
    t.string "company_name"
    t.text "notes"
    t.string "tags", default: [], null: false, array: true
    t.boolean "tax_exempt", default: false, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "search_text", default: "", null: false
    t.datetime "last_activity_at", null: false
    t.index "business_id, lower((display_name)::text), id", name: "index_clients_on_business_and_name"
    t.index ["business_id", "created_at"], name: "index_clients_on_business_id_and_created_at"
    t.index ["business_id", "last_activity_at"], name: "index_clients_on_business_id_and_last_activity_at"
    t.index ["business_id"], name: "index_clients_on_business_id"
    t.index ["search_text"], name: "index_clients_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["tags"], name: "index_clients_on_tags", using: :gin
    t.index ["uid"], name: "index_clients_on_uid", unique: true
  end

  create_table "document_sequences", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "kind", null: false
    t.bigint "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "kind"], name: "index_document_sequences_on_business_id_and_kind", unique: true
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "name", null: false
    t.string "state", default: "off", null: false
    t.integer "percentage", default: 0, null: false
    t.bigint "business_ids", default: [], null: false, array: true
    t.string "changed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_feature_flags_on_name", unique: true
  end

  create_table "industry_presets", force: :cascade do |t|
    t.string "industry", null: false
    t.integer "default_visit_minutes", default: 60, null: false
    t.jsonb "items", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["industry"], name: "index_industry_presets_on_industry", unique: true
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

  create_table "properties", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "client_id", null: false
    t.string "uid", null: false
    t.string "label"
    t.string "address_line1", null: false
    t.string "address_line2"
    t.string "city"
    t.string "region"
    t.string "postal_code"
    t.string "country", default: "US", null: false
    t.text "access_notes"
    t.boolean "billing", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_properties_on_business_id"
    t.index ["client_id"], name: "index_properties_on_client_id"
    t.index ["client_id"], name: "index_properties_one_billing_per_client", unique: true, where: "billing"
    t.index ["uid"], name: "index_properties_on_uid", unique: true
  end

  create_table "tax_rates", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "name", null: false
    t.decimal "percent", precision: 7, scale: 4, null: false
    t.boolean "applies_by_default", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "business_id, lower((name)::text)", name: "index_tax_rates_unique_active_name", unique: true, where: "(archived_at IS NULL)"
    t.index ["business_id"], name: "index_tax_rates_on_business_id"
    t.index ["uid"], name: "index_tax_rates_on_uid", unique: true
    t.check_constraint "percent > 0::numeric AND percent <= 100::numeric", name: "tax_rates_percent_range"
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
  add_foreign_key "catalog_categories", "businesses", on_delete: :cascade
  add_foreign_key "catalog_items", "businesses", on_delete: :cascade
  add_foreign_key "catalog_items", "catalog_categories", column: "category_id", on_delete: :nullify
  add_foreign_key "client_contact_methods", "businesses", on_delete: :cascade
  add_foreign_key "client_contact_methods", "clients", on_delete: :cascade
  add_foreign_key "client_link_events", "businesses", on_delete: :cascade
  add_foreign_key "client_link_events", "client_links", on_delete: :cascade
  add_foreign_key "client_links", "businesses", on_delete: :cascade
  add_foreign_key "client_links", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "client_links", "users", column: "revoked_by_id", on_delete: :nullify
  add_foreign_key "clients", "businesses", on_delete: :cascade
  add_foreign_key "document_sequences", "businesses"
  add_foreign_key "invitations", "businesses", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "accepted_by_id", on_delete: :nullify
  add_foreign_key "invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "properties", "businesses", on_delete: :cascade
  add_foreign_key "properties", "clients", on_delete: :cascade
  add_foreign_key "tax_rates", "businesses", on_delete: :cascade
  add_foreign_key "users", "businesses", column: "last_business_id", on_delete: :nullify
end
