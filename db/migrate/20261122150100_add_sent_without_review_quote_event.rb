# QTE-08: the quote's history records a send without the office's review, and why it qualified.
class AddSentWithoutReviewQuoteEvent < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :quote_events, name: "quote_events_kind",
                            expression: "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised', 'repriced', 'ready_for_review')"
    add_check_constraint :quote_events, "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised', 'repriced', 'ready_for_review', 'sent_without_review')",
                         name: "quote_events_kind"
  end
end
