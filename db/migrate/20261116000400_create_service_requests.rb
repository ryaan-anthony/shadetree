# CLI-03: the public request form. Each business gets a handle for its request page URL
# (/request/<handle>), a switch and intro text for the form; each submission is a service
# request linked to a client and property (the inbox is CLI-04).
class CreateServiceRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :businesses, :handle, :string
    # Off until an Owner or Admin turns it on: nobody gets a public form they didn't choose.
    add_column :businesses, :request_form_enabled, :boolean, default: false, null: false
    add_column :businesses, :request_form_intro, :text

    # Existing businesses get a handle from their name, made unique with a number.
    taken = []
    select_rows("SELECT id, name FROM businesses ORDER BY id").each do |id, name|
      base = name.to_s.parameterize.tr("_", "-").squeeze("-").first(30).delete_prefix("-").sub(/-+\z/, "")
      base = "business" if base.length < 3 || %w[admin api app assets help login new request requests settings shadetree signup support www].include?(base)
      handle = base
      number = 1
      handle = "#{base}-#{number += 1}" while taken.include?(handle)
      taken << handle
      execute "UPDATE businesses SET handle = #{quote(handle)} WHERE id = #{id.to_i}"
    end
    change_column_null :businesses, :handle, false
    add_index :businesses, :handle, unique: true

    create_table :service_requests do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false
      t.references :client, null: false, foreign_key: true
      t.references :property, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "new"
      t.string :source, null: false, default: "form"
      t.text :description
      t.string :timing
      # The services they picked, as they were named then: [{ "catalog_item_id", "name" }].
      t.jsonb :services, null: false, default: []
      # What they typed, kept as submitted: matching an existing client never changes it.
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.boolean :matched_existing_client, null: false, default: false
      # The service address as typed: { "address_line1", "address_line2", "city", "region", "postal_code" }.
      t.jsonb :address, null: false, default: {}
      t.timestamps
      t.check_constraint "status IN ('new', 'in_progress', 'quoted', 'archived')", name: "service_requests_status"
      t.check_constraint "source IN ('form', 'phone', 'email', 'walk_in', 'other')", name: "service_requests_source"
    end
    add_index :service_requests, :uid, unique: true
    add_index :service_requests, %i[business_id status created_at]
  end

  def down
    drop_table :service_requests
    remove_index :businesses, :handle
    remove_columns :businesses, :handle, :request_form_enabled, :request_form_intro
  end
end
