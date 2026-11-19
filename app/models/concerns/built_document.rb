# A document made in the builder (quotes, invoices): its lines arrive as the builder's full list
# of rows, matched by a browser-made key, and it holds at most MAX_LINES of them. Its line
# class includes DocumentLine and has a `key` column.
module BuiltDocument
  extend ActiveSupport::Concern

  MAX_LINES = 200

  included do
    validate :not_too_many_lines
  end

  # Makes the saved lines match `rows` (the builder's full list, in order): rows are matched
  # by their key, so autosaving again updates instead of duplicating, and saved lines missing
  # from `rows` are removed. Call inside a transaction with save.
  def sync_line_items(rows)
    rows = Array(rows).first(MAX_LINES + 1)
    by_key = line_items.index_by(&:key)
    kept = rows.each_with_index.map do |row, index|
      row = row.to_h.stringify_keys
      item = by_key[row["key"].to_s] || line_items.build(key: row["key"].presence || SecureRandom.uuid)
      item.assign_row(row, position: index)
      item
    end
    (line_items.to_a - kept).each(&:mark_for_destruction)
    @row_count = rows.size
    kept
  end

  # The rows sync_line_items takes, from another document's lines (copying a quote or a job).
  def self.rows_from(lines)
    lines.map do |line|
      line.attributes.slice(*%w[name description quantity unit taxable discount_kind]).merge(
        "key" => SecureRandom.uuid, "unit_price" => line.unit_price&.to_s, "discount_value" => line.discount_value&.to_s,
        "catalog_item" => line.catalog_item&.uid
      )
    end
  end

  private

  def not_too_many_lines
    errors.add(:base, "This #{model_name.human.downcase} can have at most #{MAX_LINES} lines.") if (@row_count || line_items.size) > MAX_LINES
  end
end
