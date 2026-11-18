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

ActiveRecord::Schema[8.1].define(version: 2026_11_18_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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
    t.datetime "welcome_dismissed_at"
    t.datetime "setup_hidden_at"
    t.jsonb "notification_emails", default: {}, null: false
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
    t.string "brand_color", default: "#047857"
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
    t.text "quote_approved_message"
    t.string "handle", null: false
    t.boolean "request_form_enabled", default: false, null: false
    t.text "request_form_intro"
    t.datetime "first_quote_sent_at"
    t.jsonb "weekly_hours"
    t.boolean "auto_create_jobs", default: true, null: false
    t.boolean "technicians_see_prices", default: false, null: false
    t.jsonb "client_visit_emails", default: {}, null: false
    t.index ["active"], name: "index_businesses_on_active"
    t.index ["handle"], name: "index_businesses_on_handle", unique: true
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
    t.datetime "undeliverable_at"
    t.string "undeliverable_reason"
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
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index "business_id, lower((display_name)::text), id", name: "index_clients_on_business_and_name"
    t.index ["business_id", "created_at"], name: "index_clients_on_business_id_and_created_at"
    t.index ["business_id", "last_activity_at"], name: "index_clients_on_business_id_and_last_activity_at"
    t.index ["business_id"], name: "index_clients_on_business_id"
    t.index ["search_text"], name: "index_clients_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["tags"], name: "index_clients_on_tags", using: :gin
    t.index ["uid"], name: "index_clients_on_uid", unique: true
  end

  create_table "closures", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "reason", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "start_minute"
    t.integer "end_minute"
    t.boolean "repeats_yearly", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "ends_on"], name: "index_closures_on_business_id_and_ends_on"
    t.index ["uid"], name: "index_closures_on_uid", unique: true
    t.check_constraint "(start_minute IS NULL) = (end_minute IS NULL) AND (start_minute IS NULL OR start_minute >= 0 AND start_minute < end_minute AND end_minute <= 1440)", name: "closures_minutes"
    t.check_constraint "ends_on >= starts_on", name: "closures_date_order"
  end

  create_table "document_sequences", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "kind", null: false
    t.bigint "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "kind"], name: "index_document_sequences_on_business_id_and_kind", unique: true
  end

  create_table "email_messages", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "kind", null: false
    t.string "to", null: false
    t.string "subject"
    t.string "related_type"
    t.bigint "related_id"
    t.string "status", default: "queued", null: false
    t.string "provider_message_id"
    t.text "error"
    t.integer "attempts", default: 0, null: false
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "bounced_at"
    t.datetime "complained_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "created_at"], name: "index_email_messages_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_email_messages_on_business_id"
    t.index ["provider_message_id"], name: "index_email_messages_on_provider_message_id", unique: true
    t.index ["related_type", "related_id"], name: "index_email_messages_on_related"
    t.index ["uid"], name: "index_email_messages_on_uid", unique: true
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'sent'::character varying::text, 'delivered'::character varying::text, 'bounced'::character varying::text, 'complained'::character varying::text, 'failed'::character varying::text, 'suppressed'::character varying::text])", name: "email_messages_status"
  end

  create_table "email_suppressions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "email", null: false
    t.string "reason", null: false
    t.bigint "email_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "email"], name: "index_email_suppressions_on_business_id_and_email", unique: true
    t.index ["business_id"], name: "index_email_suppressions_on_business_id"
    t.index ["email_message_id"], name: "index_email_suppressions_on_email_message_id"
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

  create_table "invoice_events", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "invoice_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.index ["business_id"], name: "index_invoice_events_on_business_id"
    t.index ["invoice_id", "occurred_at"], name: "index_invoice_events_on_invoice_id_and_occurred_at"
    t.index ["user_id"], name: "index_invoice_events_on_user_id"
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "invoice_id", null: false
    t.bigint "catalog_item_id"
    t.string "key", null: false
    t.integer "position", default: 0, null: false
    t.string "name", default: "", null: false
    t.text "description"
    t.decimal "quantity", precision: 12, scale: 4, default: "1.0", null: false
    t.string "unit"
    t.bigint "unit_price_cents", default: 0, null: false
    t.boolean "taxable", default: true, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_invoice_line_items_on_business_id"
    t.index ["catalog_item_id"], name: "index_invoice_line_items_on_catalog_item_id"
    t.index ["invoice_id", "key"], name: "index_invoice_line_items_on_invoice_id_and_key", unique: true
    t.index ["invoice_id", "position"], name: "index_invoice_line_items_on_invoice_id_and_position"
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying, 'amount'::character varying]::text[]))", name: "invoice_lines_discount_kind"
    t.check_constraint "quantity >= 0::numeric", name: "invoice_lines_quantity_nonnegative"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "number", null: false
    t.bigint "client_id", null: false
    t.bigint "property_id"
    t.bigint "job_id"
    t.bigint "quote_id"
    t.bigint "created_by_id"
    t.string "status", default: "draft", null: false
    t.string "currency", null: false
    t.string "title"
    t.date "issued_on", null: false
    t.string "payment_terms", default: "due_on_receipt", null: false
    t.date "due_on", null: false
    t.text "message"
    t.text "terms"
    t.text "internal_notes"
    t.jsonb "tax_rates", default: [], null: false
    t.boolean "prices_include_tax", default: false, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "discount_total_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.bigint "amount_paid_cents", default: 0, null: false
    t.datetime "sent_at"
    t.bigint "sent_by_id"
    t.datetime "voided_at"
    t.bigint "voided_by_id"
    t.string "void_reason"
    t.bigint "pdf_blob_id"
    t.string "pdf_digest"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "number"], name: "index_invoices_on_business_id_and_number", unique: true
    t.index ["business_id", "status", "due_on"], name: "index_invoices_on_business_id_and_status_and_due_on"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["client_id"], name: "index_invoices_on_client_id"
    t.index ["created_by_id"], name: "index_invoices_on_created_by_id"
    t.index ["job_id"], name: "index_invoices_on_job_id"
    t.index ["property_id"], name: "index_invoices_on_property_id"
    t.index ["quote_id"], name: "index_invoices_on_quote_id"
    t.index ["sent_by_id"], name: "index_invoices_on_sent_by_id"
    t.index ["uid"], name: "index_invoices_on_uid", unique: true
    t.index ["voided_by_id"], name: "index_invoices_on_voided_by_id"
    t.check_constraint "amount_paid_cents >= 0", name: "invoices_amount_paid_nonnegative"
    t.check_constraint "discount_amount_cents IS NULL OR discount_amount_cents >= 0", name: "invoices_discount_amount_nonnegative"
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying, 'amount'::character varying]::text[]))", name: "invoices_discount_kind"
    t.check_constraint "discount_percent IS NULL OR discount_percent >= 0::numeric AND discount_percent <= 100::numeric", name: "invoices_discount_percent_range"
    t.check_constraint "due_on >= issued_on", name: "invoices_due_after_issue"
    t.check_constraint "payment_terms::text = ANY (ARRAY['due_on_receipt'::character varying, 'net_7'::character varying, 'net_15'::character varying, 'net_30'::character varying, 'custom'::character varying]::text[])", name: "invoices_payment_terms"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'sent'::character varying, 'partially_paid'::character varying, 'paid'::character varying, 'void'::character varying]::text[])", name: "invoices_status"
  end

  create_table "job_line_items", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "job_id", null: false
    t.bigint "catalog_item_id"
    t.integer "position", default: 0, null: false
    t.string "name", default: "", null: false
    t.text "description"
    t.decimal "quantity", precision: 12, scale: 4, default: "1.0", null: false
    t.string "unit"
    t.bigint "unit_price_cents", default: 0, null: false
    t.boolean "taxable", default: true, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_item_id"], name: "index_job_line_items_on_catalog_item_id"
    t.index ["job_id", "position"], name: "index_job_line_items_on_job_id_and_position"
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying, 'amount'::character varying]::text[]))", name: "job_lines_discount_kind"
  end

  create_table "jobs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "number", null: false
    t.bigint "client_id", null: false
    t.bigint "property_id"
    t.bigint "quote_id"
    t.bigint "created_by_id"
    t.string "title", null: false
    t.text "instructions"
    t.text "internal_notes"
    t.string "status", default: "unscheduled", null: false
    t.string "currency", null: false
    t.jsonb "tax_rates", default: [], null: false
    t.boolean "prices_include_tax", default: false, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "discount_total_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "completed_at"
    t.bigint "completed_by_id"
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_id"
    t.string "cancel_reason"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "ready_to_invoice_notified_at"
    t.datetime "client_notice_due_at"
    t.index ["business_id", "number"], name: "index_jobs_on_business_id_and_number", unique: true
    t.index ["business_id", "status", "created_at"], name: "index_jobs_on_business_id_and_status_and_created_at"
    t.index ["client_id"], name: "index_jobs_on_client_id"
    t.index ["client_notice_due_at"], name: "index_jobs_on_client_notice_due_at", where: "(client_notice_due_at IS NOT NULL)"
    t.index ["created_by_id"], name: "index_jobs_on_created_by_id"
    t.index ["property_id"], name: "index_jobs_on_property_id"
    t.index ["quote_id"], name: "index_jobs_on_quote_id", unique: true
    t.index ["uid"], name: "index_jobs_on_uid", unique: true
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying, 'amount'::character varying]::text[]))", name: "jobs_discount_kind"
    t.check_constraint "status::text = ANY (ARRAY['unscheduled'::character varying, 'scheduled'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "jobs_status"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "user_id", null: false
    t.string "uid", null: false
    t.string "kind", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.bigint "actor_id"
    t.string "title", null: false
    t.string "body"
    t.string "path", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.index ["business_id", "user_id", "created_at"], name: "index_notifications_on_business_id_and_user_id_and_created_at"
    t.index ["business_id", "user_id"], name: "index_notifications_unread", where: "(read_at IS NULL)"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["uid"], name: "index_notifications_on_uid", unique: true
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

  create_table "quote_events", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "quote_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.index ["business_id", "quote_id", "occurred_at"], name: "index_quote_events_on_business_id_and_quote_id_and_occurred_at"
    t.index ["quote_id"], name: "index_quote_events_on_quote_id"
    t.index ["user_id"], name: "index_quote_events_on_user_id"
    t.check_constraint "kind::text = ANY (ARRAY['archived'::character varying::text, 'unarchived'::character varying::text, 'expiry_extended'::character varying::text, 'duplicated'::character varying::text, 'revised'::character varying::text])", name: "quote_events_kind"
  end

  create_table "quote_line_items", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "quote_id", null: false
    t.bigint "catalog_item_id"
    t.string "key", null: false
    t.integer "position", default: 0, null: false
    t.string "name", default: "", null: false
    t.text "description"
    t.decimal "quantity", precision: 12, scale: 4, default: "1.0", null: false
    t.string "unit"
    t.bigint "unit_price_cents", default: 0, null: false
    t.boolean "taxable", default: true, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_quote_line_items_on_business_id"
    t.index ["catalog_item_id"], name: "index_quote_line_items_on_catalog_item_id"
    t.index ["quote_id", "key"], name: "index_quote_line_items_on_quote_id_and_key", unique: true
    t.index ["quote_id", "position"], name: "index_quote_line_items_on_quote_id_and_position"
    t.index ["quote_id"], name: "index_quote_line_items_on_quote_id"
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying::text, 'amount'::character varying::text]))", name: "quote_lines_discount_kind"
    t.check_constraint "quantity >= 0::numeric", name: "quote_lines_quantity_nonnegative"
  end

  create_table "quote_responses", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.bigint "quote_id", null: false
    t.string "kind", null: false
    t.string "signer_name"
    t.string "email"
    t.text "message"
    t.bigint "client_link_id"
    t.bigint "recorded_by_id"
    t.string "ip_address"
    t.string "user_agent", limit: 500
    t.string "device"
    t.integer "quote_version", null: false
    t.jsonb "snapshot"
    t.string "snapshot_digest"
    t.string "signature", null: false
    t.datetime "created_at", null: false
    t.integer "revision", default: 1, null: false
    t.index ["business_id", "created_at"], name: "index_quote_responses_on_business_id_and_created_at"
    t.index ["client_link_id"], name: "index_quote_responses_on_client_link_id"
    t.index ["quote_id"], name: "index_quote_responses_on_quote_id"
    t.index ["quote_id"], name: "index_quote_responses_one_approval", unique: true, where: "((kind)::text = 'approved'::text)"
    t.index ["recorded_by_id"], name: "index_quote_responses_on_recorded_by_id"
    t.index ["uid"], name: "index_quote_responses_on_uid", unique: true
    t.check_constraint "kind::text <> 'approved'::text OR snapshot IS NOT NULL AND snapshot_digest IS NOT NULL AND signer_name IS NOT NULL", name: "quote_responses_approval_evidence"
    t.check_constraint "kind::text = ANY (ARRAY['approved'::character varying::text, 'declined'::character varying::text, 'changes_requested'::character varying::text])", name: "quote_responses_kind"
  end

  create_table "quote_revisions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "quote_id", null: false
    t.integer "number", null: false
    t.jsonb "snapshot", null: false
    t.bigint "pdf_blob_id"
    t.string "status", null: false
    t.datetime "sent_at"
    t.bigint "revised_by_id"
    t.datetime "created_at", null: false
    t.index ["business_id"], name: "index_quote_revisions_on_business_id"
    t.index ["pdf_blob_id"], name: "index_quote_revisions_on_pdf_blob_id"
    t.index ["quote_id", "number"], name: "index_quote_revisions_on_quote_id_and_number", unique: true
    t.index ["revised_by_id"], name: "index_quote_revisions_on_revised_by_id"
  end

  create_table "quote_sends", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "quote_id", null: false
    t.bigint "user_id"
    t.string "channel", null: false
    t.string "recipient"
    t.string "cc"
    t.bigint "email_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "revision", default: 1, null: false
    t.index ["business_id", "quote_id"], name: "index_quote_sends_on_business_id_and_quote_id"
    t.index ["email_message_id"], name: "index_quote_sends_on_email_message_id"
    t.index ["quote_id"], name: "index_quote_sends_on_quote_id"
    t.index ["user_id"], name: "index_quote_sends_on_user_id"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying::text, 'link'::character varying::text])", name: "quote_sends_channel"
  end

  create_table "quotes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.string "number", null: false
    t.bigint "client_id", null: false
    t.bigint "property_id"
    t.bigint "created_by_id"
    t.string "status", default: "draft", null: false
    t.string "currency", null: false
    t.string "title"
    t.text "message"
    t.text "internal_notes"
    t.text "terms"
    t.date "expires_on"
    t.jsonb "tax_rates", default: [], null: false
    t.boolean "prices_include_tax", default: false, null: false
    t.string "discount_kind"
    t.decimal "discount_percent", precision: 7, scale: 4
    t.bigint "discount_amount_cents"
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "discount_total_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "update_requested_at"
    t.bigint "pdf_blob_id"
    t.string "pdf_digest"
    t.datetime "sent_at"
    t.bigint "sent_by_id"
    t.datetime "archived_at"
    t.integer "revision", default: 1, null: false
    t.bigint "service_request_id"
    t.index ["business_id", "archived_at", "created_at"], name: "index_quotes_on_business_id_and_archived_at_and_created_at"
    t.index ["business_id", "number"], name: "index_quotes_on_business_id_and_number", unique: true
    t.index ["business_id", "status", "created_at"], name: "index_quotes_on_business_id_and_status_and_created_at"
    t.index ["business_id"], name: "index_quotes_on_business_id"
    t.index ["client_id"], name: "index_quotes_on_client_id"
    t.index ["created_by_id"], name: "index_quotes_on_created_by_id"
    t.index ["property_id"], name: "index_quotes_on_property_id"
    t.index ["sent_by_id"], name: "index_quotes_on_sent_by_id"
    t.index ["service_request_id"], name: "index_quotes_on_service_request_id"
    t.index ["uid"], name: "index_quotes_on_uid", unique: true
    t.check_constraint "discount_amount_cents IS NULL OR discount_amount_cents >= 0", name: "quotes_discount_amount_nonnegative"
    t.check_constraint "discount_kind IS NULL OR (discount_kind::text = ANY (ARRAY['percent'::character varying::text, 'amount'::character varying::text]))", name: "quotes_discount_kind"
    t.check_constraint "discount_percent IS NULL OR discount_percent >= 0::numeric AND discount_percent <= 100::numeric", name: "quotes_discount_percent_range"
  end

  create_table "service_request_notes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "service_request_id", null: false
    t.bigint "user_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_request_id"], name: "index_service_request_notes_on_service_request_id"
    t.index ["user_id"], name: "index_service_request_notes_on_user_id"
  end

  create_table "service_request_views", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "service_request_id", null: false
    t.bigint "user_id", null: false
    t.datetime "viewed_at", null: false
    t.index ["service_request_id", "user_id"], name: "index_service_request_views_on_service_request_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_service_request_views_on_user_id"
  end

  create_table "service_requests", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.bigint "client_id", null: false
    t.bigint "property_id"
    t.string "status", default: "new", null: false
    t.string "source", default: "form", null: false
    t.text "description"
    t.string "timing"
    t.jsonb "services", default: [], null: false
    t.string "contact_name"
    t.string "contact_email"
    t.string "contact_phone"
    t.boolean "matched_existing_client", default: false, null: false
    t.jsonb "address", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["business_id", "status", "created_at"], name: "idx_on_business_id_status_created_at_f13f5269d8"
    t.index ["client_id"], name: "index_service_requests_on_client_id"
    t.index ["created_by_id"], name: "index_service_requests_on_created_by_id"
    t.index ["property_id"], name: "index_service_requests_on_property_id"
    t.index ["uid"], name: "index_service_requests_on_uid", unique: true
    t.check_constraint "source::text = ANY (ARRAY['form'::character varying, 'phone'::character varying, 'email'::character varying, 'walk_in'::character varying, 'other'::character varying]::text[])", name: "service_requests_source"
    t.check_constraint "status::text = ANY (ARRAY['new'::character varying, 'in_progress'::character varying, 'quoted'::character varying, 'archived'::character varying]::text[])", name: "service_requests_status"
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

  create_table "usage_events", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "kind", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "kind", "occurred_at"], name: "index_usage_events_on_business_id_and_kind_and_occurred_at"
    t.index ["kind", "subject_type", "subject_id"], name: "index_usage_events_on_kind_and_subject_type_and_subject_id", unique: true
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

  create_table "visit_assignments", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "visit_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_visit_assignments_on_user_id"
    t.index ["visit_id", "user_id"], name: "index_visit_assignments_on_visit_id_and_user_id", unique: true
  end

  create_table "visit_events", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "visit_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.index ["visit_id"], name: "index_visit_events_on_visit_id"
    t.check_constraint "kind::text = ANY (ARRAY['scheduled'::character varying, 'rescheduled'::character varying, 'reassigned'::character varying, 'updated'::character varying, 'cancelled'::character varying, 'restored'::character varying, 'started'::character varying, 'completed'::character varying, 'reopened'::character varying]::text[])", name: "visit_events_kind"
  end

  create_table "visit_notes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "visit_id", null: false
    t.bigint "user_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["visit_id"], name: "index_visit_notes_on_visit_id"
  end

  create_table "visits", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "uid", null: false
    t.bigint "job_id", null: false
    t.date "scheduled_on", null: false
    t.string "timing", default: "anytime", null: false
    t.datetime "starts_at"
    t.datetime "window_ends_at"
    t.integer "duration_minutes", default: 60, null: false
    t.text "instructions"
    t.string "status", default: "scheduled", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.string "cancel_reason"
    t.bigint "created_by_id"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "client_note"
    t.jsonb "client_told"
    t.datetime "reminder_sent_at"
    t.index ["business_id", "scheduled_on"], name: "index_visits_on_business_id_and_scheduled_on"
    t.index ["job_id", "scheduled_on"], name: "index_visits_on_job_id_and_scheduled_on"
    t.index ["scheduled_on"], name: "index_visits_awaiting_reminder", where: "(((status)::text = 'scheduled'::text) AND (reminder_sent_at IS NULL))"
    t.index ["uid"], name: "index_visits_on_uid", unique: true
    t.check_constraint "(timing::text = 'anytime'::text) = (starts_at IS NULL) AND (timing::text = 'window'::text) = (window_ends_at IS NOT NULL)", name: "visits_times"
    t.check_constraint "duration_minutes >= 5 AND duration_minutes <= 1440", name: "visits_duration"
    t.check_constraint "status::text = ANY (ARRAY['scheduled'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "visits_status"
    t.check_constraint "timing::text = ANY (ARRAY['exact'::character varying, 'window'::character varying, 'anytime'::character varying]::text[])", name: "visits_timing"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
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
  add_foreign_key "closures", "businesses", on_delete: :cascade
  add_foreign_key "document_sequences", "businesses"
  add_foreign_key "email_messages", "businesses", on_delete: :cascade
  add_foreign_key "email_suppressions", "businesses", on_delete: :cascade
  add_foreign_key "email_suppressions", "email_messages", on_delete: :nullify
  add_foreign_key "invitations", "businesses", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "accepted_by_id", on_delete: :nullify
  add_foreign_key "invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "invoice_events", "businesses"
  add_foreign_key "invoice_events", "invoices"
  add_foreign_key "invoice_events", "users"
  add_foreign_key "invoice_line_items", "businesses"
  add_foreign_key "invoice_line_items", "catalog_items"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "businesses"
  add_foreign_key "invoices", "clients"
  add_foreign_key "invoices", "jobs"
  add_foreign_key "invoices", "properties"
  add_foreign_key "invoices", "quotes"
  add_foreign_key "invoices", "users", column: "created_by_id"
  add_foreign_key "invoices", "users", column: "sent_by_id"
  add_foreign_key "invoices", "users", column: "voided_by_id"
  add_foreign_key "job_line_items", "businesses"
  add_foreign_key "job_line_items", "catalog_items", on_delete: :nullify
  add_foreign_key "job_line_items", "jobs", on_delete: :cascade
  add_foreign_key "jobs", "businesses"
  add_foreign_key "jobs", "clients"
  add_foreign_key "jobs", "properties", on_delete: :nullify
  add_foreign_key "jobs", "quotes", on_delete: :nullify
  add_foreign_key "jobs", "users", column: "cancelled_by_id", on_delete: :nullify
  add_foreign_key "jobs", "users", column: "completed_by_id", on_delete: :nullify
  add_foreign_key "jobs", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "notifications", "businesses", on_delete: :cascade
  add_foreign_key "notifications", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "properties", "businesses", on_delete: :cascade
  add_foreign_key "properties", "clients", on_delete: :cascade
  add_foreign_key "quote_events", "businesses"
  add_foreign_key "quote_events", "quotes", on_delete: :cascade
  add_foreign_key "quote_events", "users", on_delete: :nullify
  add_foreign_key "quote_line_items", "businesses", on_delete: :cascade
  add_foreign_key "quote_line_items", "catalog_items", on_delete: :nullify
  add_foreign_key "quote_line_items", "quotes", on_delete: :cascade
  add_foreign_key "quote_responses", "businesses"
  add_foreign_key "quote_responses", "client_links", on_delete: :nullify
  add_foreign_key "quote_responses", "quotes", on_delete: :cascade
  add_foreign_key "quote_responses", "users", column: "recorded_by_id", on_delete: :nullify
  add_foreign_key "quote_revisions", "active_storage_blobs", column: "pdf_blob_id", on_delete: :nullify
  add_foreign_key "quote_revisions", "businesses"
  add_foreign_key "quote_revisions", "quotes", on_delete: :cascade
  add_foreign_key "quote_revisions", "users", column: "revised_by_id", on_delete: :nullify
  add_foreign_key "quote_sends", "businesses"
  add_foreign_key "quote_sends", "email_messages", on_delete: :nullify
  add_foreign_key "quote_sends", "quotes", on_delete: :cascade
  add_foreign_key "quote_sends", "users", on_delete: :nullify
  add_foreign_key "quotes", "active_storage_blobs", column: "pdf_blob_id", on_delete: :nullify
  add_foreign_key "quotes", "businesses", on_delete: :cascade
  add_foreign_key "quotes", "clients"
  add_foreign_key "quotes", "properties", on_delete: :nullify
  add_foreign_key "quotes", "service_requests", on_delete: :nullify
  add_foreign_key "quotes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "quotes", "users", column: "sent_by_id", on_delete: :nullify
  add_foreign_key "service_request_notes", "businesses"
  add_foreign_key "service_request_notes", "service_requests", on_delete: :cascade
  add_foreign_key "service_request_notes", "users", on_delete: :nullify
  add_foreign_key "service_request_views", "businesses"
  add_foreign_key "service_request_views", "service_requests", on_delete: :cascade
  add_foreign_key "service_request_views", "users", on_delete: :cascade
  add_foreign_key "service_requests", "businesses"
  add_foreign_key "service_requests", "clients"
  add_foreign_key "service_requests", "properties", on_delete: :nullify
  add_foreign_key "service_requests", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "tax_rates", "businesses", on_delete: :cascade
  add_foreign_key "usage_events", "businesses"
  add_foreign_key "users", "businesses", column: "last_business_id", on_delete: :nullify
  add_foreign_key "visit_assignments", "businesses", on_delete: :cascade
  add_foreign_key "visit_assignments", "users", on_delete: :cascade
  add_foreign_key "visit_assignments", "visits", on_delete: :cascade
  add_foreign_key "visit_events", "businesses", on_delete: :cascade
  add_foreign_key "visit_events", "users", on_delete: :nullify
  add_foreign_key "visit_events", "visits", on_delete: :cascade
  add_foreign_key "visit_notes", "businesses", on_delete: :cascade
  add_foreign_key "visit_notes", "users", on_delete: :nullify
  add_foreign_key "visit_notes", "visits", on_delete: :cascade
  add_foreign_key "visits", "businesses", on_delete: :cascade
  add_foreign_key "visits", "jobs", on_delete: :cascade
  add_foreign_key "visits", "users", column: "created_by_id", on_delete: :nullify
end
