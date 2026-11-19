require "csv"

# INS-02: one CSV a business can download. Columns are documented here and on the page, and are
# kept stable: add new ones at the end, never rename or reorder. Money is a plain decimal in the
# document's currency ("1240.00"); dates are YYYY-MM-DD; times are YYYY-MM-DD HH:MM in the
# business's time zone; lists are joined with "; ". Cells a spreadsheet would run as a formula
# are prefixed with '.
class DataExport::Table
  Column = Data.define(:header, :value)

  attr_reader :key, :label, :description, :columns

  def initialize(key, label, description, scope:, &columns)
    @key, @label, @description, @scope = key, label, description, scope
    @columns = []
    instance_exec(&columns)
  end

  def column(header, &value) = @columns << Column.new(header:, value:)

  def records = @scope.call

  # The CSV, and how many rows it has. Run inside the business.
  def generate
    count = 0
    zone = Current.business.time_zone
    csv = CSV.generate do |rows|
      rows << columns.map(&:header)
      records.find_each do |record|
        rows << columns.map { |column| cell(column.value.call(record), zone) }
        count += 1
      end
    end
    [ csv, count ]
  end

  def filename = "#{key}.csv"

  def self.money(cents) = cents && format("%s%d.%02d", cents.negative? ? "-" : "", cents.abs / 100, cents.abs % 100)

  private

  def cell(value, zone)
    text = case value
    when nil then ""
    when Time, ActiveSupport::TimeWithZone, DateTime then value.in_time_zone(zone).strftime("%Y-%m-%d %H:%M")
    when Date then value.iso8601
    when Array then value.compact_blank.join("; ")
    when true then "yes"
    when false then "no"
    else value.to_s
    end
    text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
  end
end
