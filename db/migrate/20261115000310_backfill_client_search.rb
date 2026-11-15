# CLI-02 (2/3): fill search_text and last_activity_at for existing clients, in batches so no
# long lock is held, and before the trigram index exists so rows aren't indexed twice. Safe
# to re-run (bin/rails clients:reindex_search does the same later if needed).
class BackfillClientSearch < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH = 1_000

  def up
    max = select_value("SELECT max(id) FROM clients").to_i
    (0..max).step(BATCH) do |from|
      execute <<~SQL.squish
        UPDATE clients SET last_activity_at = updated_at,
          search_text = lower(concat_ws(' ', clients.display_name, clients.company_name,
            (SELECT string_agg(concat_ws(' ', m.value, CASE WHEN m.kind = 'phone' THEN m.normalized END), ' ')
               FROM client_contact_methods m WHERE m.client_id = clients.id),
            (SELECT string_agg(concat_ws(' ', p.label, p.address_line1, p.address_line2, p.city, p.region, p.postal_code), ' ')
               FROM properties p WHERE p.client_id = clients.id)))
        WHERE id > #{from} AND id <= #{from + BATCH}
      SQL
    end
  end

  def down; end
end
