# What changed between two quote snapshots (QTE-06), in words for staff:
#
#   QuoteRevisionDiff.new(old, new).changes
#   # => ["Removed Bed edging", "Mulch install: quantity 6 → 4", "Total $1,297.42 → $1,189.74"]
#
# Lines are matched by name (a renamed line reads as removed and added).
class QuoteRevisionDiff
  LINE_FIELDS = { "description" => "description", "quantity" => "quantity", "unit" => "unit", "unit_price_cents" => "price",
                  "taxable" => "tax", "discount_value" => "discount" }.freeze
  FIELDS = { "title" => "Title", "message" => "Message", "terms" => "Terms", "property" => "Property", "discount" => "Discount",
             "tax_rates" => "Taxes", "prices_include_tax" => "Tax-inclusive pricing", "files" => "Files" }.freeze

  def initialize(before, after)
    @before = before || {}
    @after = after || {}
  end

  def changes
    field_changes + line_changes + expiry_change + total_change
  end

  private

  attr_reader :before, :after

  def field_changes
    FIELDS.filter_map do |key, label|
      from, to = before[key], after[key]
      from, to = [ from, to ].map { |files| Array(files).map { _1["filename"] }.sort } if key == "files"
      "#{label} changed" if from != to
    end
  end

  # Lines are keyed by name and occurrence, so two lines with the same name are compared in order.
  def keyed(lines) = Array(lines).group_by { _1["name"] }.flat_map { |name, group| group.each_with_index.map { |line, i| [ [ name, i ], line ] } }.to_h

  def line_changes
    old_lines = keyed(before["lines"])
    new_lines = keyed(after["lines"])
    name_of = ->(line_key) { line_key[0].presence || "an untitled line" }
    removed = (old_lines.keys - new_lines.keys).map { "Removed #{name_of.(_1)}" }
    added = (new_lines.keys - old_lines.keys).map { "Added #{name_of.(_1)}" }
    changed = (old_lines.keys & new_lines.keys).filter_map do |line_key|
      diffs = LINE_FIELDS.filter_map { |field, label| field_change(field, label, old_lines[line_key][field], new_lines[line_key][field]) }
      "#{name_of.(line_key)}: #{diffs.join(", ")}" if diffs.any?
    end
    removed + added + changed
  end

  def field_change(field, label, from, to)
    return if same?(from, to)
    return "#{label} #{money(from)} → #{money(to)}" if field == "unit_price_cents"
    return "#{label} #{number(from)} → #{number(to)}" if field.in?(%w[quantity discount_value])

    "#{label} changed"
  end

  def expiry_change
    return [] if before["expires_on"] == after["expires_on"]

    [ "Valid until #{date(before["expires_on"])} → #{date(after["expires_on"])}" ]
  end

  def total_change
    from, to = before.dig("totals", "total_cents"), after.dig("totals", "total_cents")
    from == to ? [] : [ "Total #{money(from)} → #{money(to)}" ]
  end

  def same?(from, to) = from.to_s.sub(/\.0+\z/, "") == to.to_s.sub(/\.0+\z/, "")
  def money(cents) = cents.nil? ? "none" : Money.new(cents.to_i, after["currency"] || before["currency"]).format
  def number(value) = value.nil? ? "none" : value.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")
  def date(value) = value ? I18n.l(Date.parse(value)) : "no date"
end
