# MKT-02 part 2: operators mark a contact message handled once it's been answered.
class AddHandledAtToContactMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :contact_messages, :handled_at, :datetime
  end
end
