# QTE-08: services technicians may send without the office's review, the business's optional cap
# on such quotes' totals, and the catalog price a quote line was added at (so a line whose
# service's price changed since reads "the price list changed", not "price changed").
class AddSendWithoutReview < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_items, :send_without_review, :boolean, default: false, null: false
    add_column :businesses, :without_review_cap_cents, :bigint
    add_column :quote_line_items, :catalog_price_cents, :bigint
  end
end
