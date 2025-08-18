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

ActiveRecord::Schema[8.0].define(version: 2025_08_18_232549) do
  create_table "business_closures", force: :cascade do |t|
    t.integer "location_id", null: false
    t.date "date", null: false
    t.string "reason", null: false
    t.boolean "is_full_day", default: true
    t.time "modified_open_time"
    t.time "modified_close_time"
    t.boolean "is_recurring", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_business_closures_on_date"
    t.index ["is_recurring"], name: "index_business_closures_on_is_recurring"
    t.index ["location_id", "date"], name: "index_business_closures_on_location_and_date", unique: true
    t.index ["location_id"], name: "index_business_closures_on_location_id"
  end

  create_table "business_roles", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.text "description"
    t.json "permissions"
    t.boolean "is_default", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "name"], name: "index_business_roles_on_business_and_name", unique: true
    t.index ["business_id"], name: "index_business_roles_on_business_id"
    t.index ["is_default"], name: "index_business_roles_on_is_default"
  end

  create_table "businesses", force: :cascade do |t|
    t.string "name", null: false
    t.string "timezone"
    t.string "email", null: false
    t.string "phone"
    t.string "website"
    t.string "currency", default: "USD"
    t.string "brand_color", default: "#059669"
    t.string "logo_url"
    t.boolean "active", default: true
    t.integer "owner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_businesses_on_active"
    t.index ["email"], name: "index_businesses_on_email"
    t.index ["owner_id"], name: "index_businesses_on_owner_id"
  end

  create_table "customer_notification_preferences", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.integer "business_id", null: false
    t.boolean "email_notifications", default: true
    t.boolean "sms_notifications", default: true
    t.boolean "booking_confirmations", default: true
    t.boolean "appointment_reminders", default: true
    t.boolean "payment_notifications", default: true
    t.boolean "promotional_messages", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_customer_notification_preferences_on_business_id"
    t.index ["customer_id", "business_id"], name: "index_customer_notification_prefs_on_customer_and_business", unique: true
    t.index ["customer_id"], name: "index_customer_notification_preferences_on_customer_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "timezone"
    t.text "address", null: false
    t.string "city", null: false
    t.string "state", null: false
    t.string "zip_code", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.boolean "is_primary", default: false
    t.string "phone"
    t.string "email"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_locations_on_active"
    t.index ["business_id"], name: "index_locations_on_business_id"
    t.index ["is_primary"], name: "index_locations_on_is_primary"
    t.index ["latitude", "longitude"], name: "index_locations_on_latitude_and_longitude"
  end

  create_table "message_templates", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "event", null: false
    t.string "message_type", null: false
    t.text "message_content", null: false
    t.string "subject_line"
    t.boolean "is_active", default: true
    t.integer "usage_count", default: 0
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "event"], name: "index_message_templates_on_business_id_and_event"
    t.index ["business_id", "message_type"], name: "index_message_templates_on_business_id_and_message_type"
    t.index ["business_id"], name: "index_message_templates_on_business_id"
  end

  create_table "notification_triggers", force: :cascade do |t|
    t.integer "business_id", null: false
    t.integer "message_template_id", null: false
    t.string "trigger_name", null: false
    t.string "trigger_event", null: false
    t.json "trigger_conditions", default: {}
    t.integer "timing_offset", default: 0
    t.boolean "is_active", default: true
    t.json "delivery_channels", default: {}
    t.datetime "last_triggered_at"
    t.integer "trigger_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "is_active"], name: "index_notification_triggers_on_business_id_and_is_active"
    t.index ["business_id", "trigger_event"], name: "index_notification_triggers_on_business_id_and_trigger_event"
    t.index ["business_id"], name: "index_notification_triggers_on_business_id"
    t.index ["message_template_id"], name: "index_notification_triggers_on_message_template_id"
  end

  create_table "operating_hours", force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "day_of_week", null: false
    t.time "open_time"
    t.time "close_time"
    t.boolean "is_closed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day_of_week"], name: "index_operating_hours_on_day_of_week"
    t.index ["location_id", "day_of_week"], name: "index_operating_hours_on_location_and_day", unique: true
    t.index ["location_id"], name: "index_operating_hours_on_location_id"
  end

  create_table "service_area_restrictions", force: :cascade do |t|
    t.integer "service_area_id", null: false
    t.string "restriction_type", null: false
    t.string "city"
    t.string "state"
    t.string "zip_code"
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["restriction_type", "city"], name: "index_service_area_restrictions_on_restriction_type_and_city"
    t.index ["restriction_type", "state"], name: "index_service_area_restrictions_on_restriction_type_and_state"
    t.index ["restriction_type", "zip_code"], name: "idx_on_restriction_type_zip_code_547620d69b"
    t.index ["restriction_type"], name: "index_service_area_restrictions_on_restriction_type"
    t.index ["service_area_id"], name: "index_service_area_restrictions_on_service_area_id"
  end

  create_table "service_areas", force: :cascade do |t|
    t.integer "location_id", null: false
    t.decimal "radius", precision: 8, scale: 2
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_areas_on_active"
    t.index ["location_id"], name: "index_service_areas_on_location_id"
  end

  create_table "service_categories", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "parent_id"
    t.integer "sort_order", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_categories_on_active"
    t.index ["business_id", "parent_id", "name"], name: "index_service_categories_on_business_parent_name", unique: true
    t.index ["business_id"], name: "index_service_categories_on_business_id"
    t.index ["parent_id"], name: "index_service_categories_on_parent_id"
    t.index ["sort_order"], name: "index_service_categories_on_sort_order"
  end

  create_table "service_fees", force: :cascade do |t|
    t.integer "service_id", null: false
    t.integer "location_id"
    t.string "fee_name", null: false
    t.decimal "fee_amount", precision: 8, scale: 4, null: false
    t.string "fee_type", null: false
    t.boolean "is_mandatory", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fee_type"], name: "index_service_fees_on_fee_type"
    t.index ["is_mandatory"], name: "index_service_fees_on_is_mandatory"
    t.index ["location_id"], name: "index_service_fees_on_location_id"
    t.index ["service_id", "location_id", "fee_name"], name: "index_service_fees_on_service_location_name", unique: true
    t.index ["service_id"], name: "index_service_fees_on_service_id"
  end

  create_table "service_prices", force: :cascade do |t|
    t.integer "service_id", null: false
    t.integer "location_id", null: false
    t.decimal "base_price", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD"
    t.date "effective_date"
    t.date "expires_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency"], name: "index_service_prices_on_currency"
    t.index ["effective_date"], name: "index_service_prices_on_effective_date"
    t.index ["expires_date"], name: "index_service_prices_on_expires_date"
    t.index ["location_id"], name: "index_service_prices_on_location_id"
    t.index ["service_id", "location_id"], name: "index_service_prices_on_service_and_location", unique: true
    t.index ["service_id"], name: "index_service_prices_on_service_id"
  end

  create_table "service_taxes", force: :cascade do |t|
    t.integer "service_id", null: false
    t.integer "location_id"
    t.string "tax_name", null: false
    t.decimal "tax_rate", precision: 8, scale: 4, null: false
    t.string "tax_type", null: false
    t.boolean "is_inclusive", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_inclusive"], name: "index_service_taxes_on_is_inclusive"
    t.index ["location_id"], name: "index_service_taxes_on_location_id"
    t.index ["service_id", "location_id", "tax_name"], name: "index_service_taxes_on_service_location_name", unique: true
    t.index ["service_id"], name: "index_service_taxes_on_service_id"
    t.index ["tax_type"], name: "index_service_taxes_on_tax_type"
  end

  create_table "services", force: :cascade do |t|
    t.integer "business_id", null: false
    t.integer "service_category_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "duration", null: false
    t.boolean "requires_location", default: false
    t.boolean "is_active", default: true
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "name"], name: "index_services_on_business_and_name", unique: true
    t.index ["business_id"], name: "index_services_on_business_id"
    t.index ["is_active"], name: "index_services_on_is_active"
    t.index ["requires_location"], name: "index_services_on_requires_location"
    t.index ["service_category_id"], name: "index_services_on_service_category_id"
    t.index ["sort_order"], name: "index_services_on_sort_order"
  end

  create_table "special_availabilities", force: :cascade do |t|
    t.integer "location_id", null: false
    t.date "date", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_special_availabilities_on_date"
    t.index ["location_id", "date"], name: "index_special_availabilities_on_location_and_date", unique: true
    t.index ["location_id"], name: "index_special_availabilities_on_location_id"
  end

  create_table "staff_availabilities", force: :cascade do |t|
    t.integer "staff_member_id", null: false
    t.integer "location_id"
    t.integer "day_of_week", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.boolean "is_available", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day_of_week"], name: "index_staff_availabilities_on_day_of_week"
    t.index ["is_available"], name: "index_staff_availabilities_on_is_available"
    t.index ["location_id"], name: "index_staff_availabilities_on_location_id"
    t.index ["staff_member_id", "day_of_week", "location_id"], name: "index_staff_availabilities_on_staff_day_location", unique: true
    t.index ["staff_member_id"], name: "index_staff_availabilities_on_staff_member_id"
  end

  create_table "staff_members", force: :cascade do |t|
    t.integer "business_id", null: false
    t.integer "user_id", null: false
    t.string "status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "user_id"], name: "index_staff_members_on_business_and_user", unique: true
    t.index ["business_id"], name: "index_staff_members_on_business_id"
    t.index ["status"], name: "index_staff_members_on_status"
    t.index ["user_id"], name: "index_staff_members_on_user_id"
  end

  create_table "staff_roles", force: :cascade do |t|
    t.integer "staff_member_id", null: false
    t.integer "business_role_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_role_id"], name: "index_staff_roles_on_business_role_id"
    t.index ["staff_member_id", "business_role_id"], name: "index_staff_roles_on_staff_member_and_role", unique: true
    t.index ["staff_member_id"], name: "index_staff_roles_on_staff_member_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_tier"
    t.string "first_name"
    t.string "last_name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "business_closures", "locations"
  add_foreign_key "business_roles", "businesses"
  add_foreign_key "businesses", "users", column: "owner_id"
  add_foreign_key "customer_notification_preferences", "businesses"
  add_foreign_key "customer_notification_preferences", "users", column: "customer_id"
  add_foreign_key "locations", "businesses"
  add_foreign_key "message_templates", "businesses"
  add_foreign_key "notification_triggers", "businesses"
  add_foreign_key "notification_triggers", "message_templates"
  add_foreign_key "operating_hours", "locations"
  add_foreign_key "service_area_restrictions", "service_areas"
  add_foreign_key "service_areas", "locations"
  add_foreign_key "service_categories", "businesses"
  add_foreign_key "service_categories", "service_categories", column: "parent_id"
  add_foreign_key "service_fees", "locations"
  add_foreign_key "service_fees", "services"
  add_foreign_key "service_prices", "locations"
  add_foreign_key "service_prices", "services"
  add_foreign_key "service_taxes", "locations"
  add_foreign_key "service_taxes", "services"
  add_foreign_key "services", "businesses"
  add_foreign_key "services", "service_categories"
  add_foreign_key "special_availabilities", "locations"
  add_foreign_key "staff_availabilities", "locations"
  add_foreign_key "staff_availabilities", "staff_members"
  add_foreign_key "staff_members", "businesses"
  add_foreign_key "staff_members", "users"
  add_foreign_key "staff_roles", "business_roles"
  add_foreign_key "staff_roles", "staff_members"
end
