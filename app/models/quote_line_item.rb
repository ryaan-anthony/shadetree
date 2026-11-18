# One line on a quote (QTE-01): a copy of a catalog item or a custom line. Amounts are cents
# in the quote's currency; Pricing::Line does the arithmetic. Shared with job lines through
# DocumentLine.
class QuoteLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  belongs_to :quote, inverse_of: :line_items
  belongs_to :catalog_item, optional: true # set only through catalog_item_id_for, within the business

  def document_currency = quote.currency

  before_validation { self.business ||= quote&.business }

  validates :key, presence: true, length: { maximum: 64 }

  # Fills this line from one row of the builder form.
  def assign_row(row, position:)
    self.position = position
    self.catalog_item_id = catalog_item_id_for(row["catalog_item"].to_s) if row.key?("catalog_item")
    %w[name description unit].each { public_send("#{_1}=", row[_1]) if row.key?(_1) }
    self.quantity = row["quantity"].to_s.strip.presence || "0" if row.key?("quantity")
    self.unit_price = row["unit_price"].to_s.strip.presence || "0" if row.key?("unit_price")
    self.taxable = ActiveModel::Type::Boolean.new.cast(row["taxable"]) if row.key?("taxable")
    set_discount(row["discount_kind"], row["discount_value"]) if row.key?("discount_kind")
  end
end
