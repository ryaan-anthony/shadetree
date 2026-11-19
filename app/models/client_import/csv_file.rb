require "csv"

# CLI-06: reading an uploaded client list. Spreadsheets and other tools export CSVs in many
# shapes: UTF-8 with or without a byte-order mark, UTF-16 (Excel's "Unicode text"), Windows-1252
# (older Excel), and commas, semicolons (European Excel) or tabs. The first non-blank row is the
# header; blank rows are dropped.
class ClientImport::CsvFile
  MAX_BYTES = 2.megabytes
  MAX_ROWS = 5_000
  MAX_COLUMNS = 60

  class Invalid < StandardError; end

  attr_reader :headers, :rows

  def self.read(data) = new(data)

  def initialize(data)
    raise Invalid, "The file is empty." if data.blank?
    raise Invalid, "The file is larger than #{MAX_BYTES / 1.megabyte} MB. Split it into smaller files." if data.bytesize > MAX_BYTES

    text = decode(data)
    raise Invalid, "This doesn't look like a CSV file. Export your list as CSV and try again." if text.include?("\u0000")

    table = CSV.parse(text, col_sep: separator(text), liberal_parsing: true).map { |row| row.map { _1.to_s.strip } }
    table.reject! { |row| row.all?(&:blank?) }
    raise Invalid, "The file has no rows." if table.empty?

    @headers = table.shift.first(MAX_COLUMNS).each_with_index.map { |header, index| header.presence || "Column #{index + 1}" }
    raise Invalid, "The file has a header row but no clients under it." if table.empty?
    raise Invalid, "The file has #{table.size} rows; the limit is #{MAX_ROWS}. Split it into smaller files." if table.size > MAX_ROWS

    @rows = table.map { |row| row.first(@headers.size).fill("", row.size...@headers.size) }
  rescue CSV::MalformedCSVError => error
    raise Invalid, "The file couldn't be read as CSV (#{error.message.sub(/ in line \d+\.?/, "")}, around row #{error.line_number})."
  end

  private

  def decode(data)
    data = data.b
    text =
      if data.start_with?("\xEF\xBB\xBF".b) then data.byteslice(3..).force_encoding(Encoding::UTF_8)
      elsif data.start_with?("\xFF\xFE".b) then data.byteslice(2..).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
      elsif data.start_with?("\xFE\xFF".b) then data.byteslice(2..).force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8)
      elsif (utf8 = data.dup.force_encoding(Encoding::UTF_8)).valid_encoding? then utf8
      else data.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
    text.encode(universal_newline: true)
  rescue EncodingError
    raise Invalid, "The file's text encoding couldn't be read. Save it as CSV UTF-8 and try again."
  end

  # The separator used most in the header line.
  def separator(text)
    header = text.each_line.find { _1.strip.present? }.to_s
    [ ",", ";", "\t" ].max_by { header.count(_1) }
  end
end
