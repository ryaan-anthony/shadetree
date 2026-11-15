# CLI-02: fast substring search over clients and a "recent activity" sort.
#
# search_text is a lowercased digest of the client's name, company, emails, phones (as typed
# and as digits) and property addresses, kept current by the models. A trigram index makes
# "contains" searches fast at tens of thousands of clients per business.
class AddSearchToClients < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # concurrent index builds

  def up
    enable_extension "pg_trgm"
    add_column :clients, :search_text, :text, null: false, default: ""
    add_column :clients, :last_activity_at, :datetime
    execute "UPDATE clients SET last_activity_at = updated_at"
    change_column_null :clients, :last_activity_at, false

    add_index :clients, :search_text, using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently
    add_index :clients, "business_id, lower(display_name), id", name: "index_clients_on_business_and_name", algorithm: :concurrently
    add_index :clients, %i[business_id created_at], algorithm: :concurrently
    add_index :clients, %i[business_id last_activity_at], algorithm: :concurrently

    # Backfill in SQL (the same fields Client#build_search_text uses; the next save of each
    # client rewrites it from Ruby anyway).
    execute <<~SQL
      UPDATE clients SET search_text = lower(concat_ws(' ',
        clients.display_name, clients.company_name,
        (SELECT string_agg(concat_ws(' ', m.value, CASE WHEN m.kind = 'phone' THEN m.normalized END), ' ')
           FROM client_contact_methods m WHERE m.client_id = clients.id),
        (SELECT string_agg(concat_ws(' ', p.label, p.address_line1, p.address_line2, p.city, p.region, p.postal_code), ' ')
           FROM properties p WHERE p.client_id = clients.id)))
    SQL
  end

  def down
    remove_index :clients, %i[business_id last_activity_at]
    remove_index :clients, %i[business_id created_at]
    remove_index :clients, name: "index_clients_on_business_and_name"
    remove_index :clients, :search_text
    remove_column :clients, :last_activity_at
    remove_column :clients, :search_text
  end
end
