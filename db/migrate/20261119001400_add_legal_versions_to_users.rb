# MKT-03: which Terms and Privacy versions each person accepted (and when, terms_accepted_at).
# Blank means the placeholder terms from before versions were recorded.
class AddLegalVersionsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :terms_version, :string
    add_column :users, :privacy_version, :string
  end
end
