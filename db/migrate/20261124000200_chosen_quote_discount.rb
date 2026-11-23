# PAY-08 (owner, 2026-11-23): staff choose how much of a quote's discount an invoice applies. The
# choice is kept apart from the applied amount (quote_discount_share_cents), which is the choice
# held between the minimum the work left needs and what's left of the discount. Nil: not chosen
# ($0, "Apply later").
class ChosenQuoteDiscount < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :quote_discount_chosen_cents, :bigint
    add_check_constraint :invoices, "quote_discount_chosen_cents IS NULL OR quote_discount_chosen_cents >= 0", name: "invoices_quote_discount_chosen_nonnegative"
  end
end
