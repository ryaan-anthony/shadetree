require "csv"

# INS-02: one CSV a business can download. Columns are documented here and on the page, and are
# kept stable: add new ones at the end, never rename or reorder. Money is a plain decimal in the
# document's currency ("1240.00"); dates are YYYY-MM-DD; times are YYYY-MM-DD HH:MM in the
# business's time zone; lists are joined with "; ". Text a spreadsheet would run as a formula is
# prefixed with ' (numbers we write, and phone numbers, are left alone). Files start with a
# byte-order mark, so Excel opens them as UTF-8.
class DataExport::Table
  Column = Data.define(:header, :value, :number, :flag)
  BOM = "﻿".freeze
  PHONE = /\A[+-]?[\d\s().-]+\z/

  attr_reader :key, :label, :description

  # cursor: the (non-null, unique together) columns rows come out in, read in batches. flag: a
  # release flag (PLT-11) the table, or a column, is shown under, for the current business.
  def initialize(key, label, description, scope:, cursor: :id, flag: nil, &columns)
    @key, @label, @description, @scope, @cursor, @flag = key, label, description, scope, cursor, flag
    @columns = []
    instance_exec(&columns)
  end

  def column(header, number: false, flag: nil, &value) = @columns << Column.new(header:, value:, number:, flag:)

  def columns = @columns.select { _1.flag.nil? || Feature.enabled?(_1.flag) }
  def available? = @flag.nil? || Feature.enabled?(@flag)

  def records = @scope.call

  # Writes the CSV to io (a String or a file); returns how many rows it has. Run inside the
  # business.
  def write(io)
    count = 0
    zone = Current.business.time_zone
    shown = columns # flags are checked once per file, not per row
    io << BOM << CSV.generate_line(shown.map(&:header))
    records.find_each(cursor: @cursor) do |record|
      io << CSV.generate_line(shown.map { |column| cell(column.value.call(record), zone, column.number) })
      count += 1
    end
    count
  end

  # The CSV as a string, and its row count.
  def generate
    csv = +""
    count = write(csv)
    [ csv, count ]
  end

  def filename = "#{key}.csv"

  def self.money(cents, currency) = cents && Money.new(cents, currency).to_s

  private

  def cell(value, zone, number)
    text = case value
    when nil then ""
    when Time, ActiveSupport::TimeWithZone, DateTime then value.in_time_zone(zone).strftime("%Y-%m-%d %H:%M")
    when Date then value.iso8601
    when Array then value.compact_blank.join("; ")
    when true then "yes"
    when false then "no"
    else value.to_s
    end
    return text if number || text.match?(PHONE)

    text.lstrip.match?(/\A[=+\-@\t\r＝＋－＠]/) ? "'#{text}" : text
  end
end
