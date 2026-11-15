# CLI-02 (3/3): a trigram index for "contains" search, and indexes behind the three sorts.
# Built concurrently (no write lock) and guarded so an interrupted run can be retried.
class AddClientSearchIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :clients, :search_text, using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently, if_not_exists: true
    add_index :clients, "business_id, lower(display_name), id", name: "index_clients_on_business_and_name",
              algorithm: :concurrently, if_not_exists: true
    add_index :clients, %i[business_id created_at], algorithm: :concurrently, if_not_exists: true
    add_index :clients, %i[business_id last_activity_at], algorithm: :concurrently, if_not_exists: true
  end
end
