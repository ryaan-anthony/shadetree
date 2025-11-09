class ChangeBusinessEmailToNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :businesses, :email, true
  end
end

