# What changed between two quote snapshots (QTE-06), in words for staff:
#
#   QuoteRevisionDiff.new(old, new).changes
#   # => ["Removed Bed edging", "Mulch install: quantity 6 → 4", "Total $1,297.42 → $1,189.74"]
#
# Lines are matched by name (a renamed line reads as removed and added).
class QuoteRevisionDiff
  LINE_FIELDS = { "description" => "description", "quantity" => "quantity", "unit" => "unit", "unit_price_cents" => "price",
                  "taxable" => "tax", "discount_value" => "discount" }.freeze
  FIELDS = { "title" => "Title", "message" => "Message", "terms" => "Terms", "property" => "Property" }.freeze

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
    FIELDS.filter_map { |key, label| "#{label} changed" if before[key] != after[key] }
  end

  def line_changes
    old_lines = (before["lines"] || []).index_by { _1["name"] }
    new_lines = (after["lines"] || []).index_by { _1["name"] }
    removed = (old_lines.keys - new_lines.keys).map { "Removed #{_1.presence || "an untitled line"}" }
    added = (new_lines.keys - old_lines.keys).map { "Added #{_1.presence || "an untitled line"}" }
    changed = (old_lines.keys & new_lines.keys).filter_map do |name|
      diffs = LINE_FIELDS.filter_map do |key, label|
        from, to = old_lines[name][key], new_lines[name][key]
        next if same?(from, to)

        key == "unit_price_cents" ? "#{label} #{money(from)} → #{money(to)}" : (key.in?(%w[quantity discount_value]) ? "#{label} #{number(from)} → #{number(to)}" : "#{label} changed")
      end
      "#{name}: #{diffs.join(", ")}" if diffs.any?
    end
    removed + added + changed
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
