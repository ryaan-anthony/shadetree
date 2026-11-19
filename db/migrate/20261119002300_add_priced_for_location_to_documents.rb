# CAT-08: the location a draft's lines were priced for, so moving it to another location can
# offer that location's prices until staff accept or keep them; and quote history records it.
class AddPricedForLocationToDocuments < ActiveRecord::Migration[8.1]
  def change
    %i[quotes invoices].each do |table|
      add_reference table, :priced_for_location, foreign_key: { to_table: :locations, on_delete: :nullify }, index: false
    end

    remove_check_constraint :quote_events, "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised')", name: "quote_events_kind"
    add_check_constraint :quote_events, "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised', 'repriced')", name: "quote_events_kind"
  end
end
