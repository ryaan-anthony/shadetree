# CLI-04: the request inbox. Who has opened each request, internal notes, who logged a phone
# or walk-in request, and which quotes came from a request.
class CreateRequestInbox < ActiveRecord::Migration[8.1]
  def change
    add_reference :service_requests, :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :quotes, :service_request, foreign_key: { on_delete: :nullify }

    create_table :service_request_views do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :service_request, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :viewed_at, null: false
    end
    add_index :service_request_views, %i[service_request_id user_id], unique: true

    create_table :service_request_notes do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :service_request, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :body, null: false
      t.timestamps
    end
  end
end
