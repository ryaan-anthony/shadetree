# INS-02: a client whose personal data was erased at their request. The row stays (quotes,
# invoices and payments point to it) as "Erased client".
class AddErasedAtToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :erased_at, :datetime
  end
end
