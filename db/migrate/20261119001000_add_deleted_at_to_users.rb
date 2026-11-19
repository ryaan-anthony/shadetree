# ACC-06: a deleted account keeps its row, so the records it made still point somewhere, but
# everything personal is removed and it shows as "Former member".
class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime
  end
end
