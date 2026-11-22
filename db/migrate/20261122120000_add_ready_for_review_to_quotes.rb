# QTE-07: a member who quotes their assigned requests, but doesn't send, marks their draft ready
# for the office to check and send; the quote's history records it.
class AddReadyForReviewToQuotes < ActiveRecord::Migration[8.1]
  def change
    change_table :quotes, bulk: true do |t|
      t.datetime :ready_for_review_at
      t.references :ready_for_review_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
    end
    remove_check_constraint :quote_events, name: "quote_events_kind",
                            expression: "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised', 'repriced')"
    add_check_constraint :quote_events, "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised', 'repriced', 'ready_for_review')",
                         name: "quote_events_kind"
  end
end
