# QTE-08: services technicians may send without the office's review, the business's optional cap
# on such quotes' totals, and the catalog price a quote line was added at (so a line whose
# service's price changed since reads "the price list changed", not "price changed").
class AddSendWithoutReview < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_items, :send_without_review, :boolean, default: false, null: false
    add_column :businesses, :without_review_cap_cents, :bigint
    add_column :quote_line_items, :catalog_price_cents, :bigint

    # Drafts already started: their service lines count as added at today's price at the quote's
    # location, so a later price list change isn't read as the technician changing the price.
    up_only do
      execute <<~SQL.squish
        UPDATE quote_line_items AS li
        SET catalog_price_cents = COALESCE(
          (SELECT lp.unit_price_cents FROM location_prices lp JOIN locations l ON l.id = lp.location_id
           WHERE lp.catalog_item_id = li.catalog_item_id AND lp.location_id = q.location_id AND NOT l."primary"),
          ci.unit_price_cents)
        FROM quotes q, catalog_items ci
        WHERE q.id = li.quote_id AND ci.id = li.catalog_item_id AND q.status = 'draft'
      SQL
    end
  end
end
