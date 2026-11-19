require "csv"

# CLI-06: reading an uploaded client list. Spreadsheets and other tools export CSVs in many
# shapes: UTF-8 with or without a byte-order mark, UTF-16 (Excel's "Unicode text"), Windows-1252
# (older Excel), and commas, semicolons (European Excel) or tabs. The first non-blank row is the
# header; blank rows are dropped.
class ClientImport::CsvFile
  MAX_BYTES = 2.megabytes
  MAX_ROWS = 5_000
  MAX_COLUMNS = 150
  MAX_CELL = 1_000 # characters kept per cell (and 100 per header)

  class Invalid < StandardError; end

  # rows: the values, one array per row; line_numbers: where each row starts in the file (blank
  # lines and multi-line cells count), for messages about a row; ignored_columns: past MAX_COLUMNS.
  attr_reader :headers, :rows, :line_numbers, :ignored_columns

  def self.read(data) = new(data)

  def initialize(data)
    raise Invalid, "The file is empty." if data.blank?
    raise Invalid, "The file is larger than #{MAX_BYTES / 1.megabyte} MB. Split it into smaller files." if data.bytesize > MAX_BYTES

    text = decode(data)
    raise Invalid, "This doesn't look like a CSV file. Export your list as CSV and try again." if text.include?("\u0000")

    table = []
    csv = CSV.new(text, col_sep: separator(text), liberal_parsing: true)
    line = 1 # physical line a row starts on (CSV's own lineno counts records, not lines)
    loop do
      row = csv.shift or break
      start, line = line, line + [ csv.line.to_s.count("\n"), 1 ].max
      row = row.map { _1.to_s.strip.first(MAX_CELL) }
      table << [ start, row ] unless row.all?(&:blank?)
      raise Invalid, "The file has more than #{MAX_ROWS} rows. Split it into smaller files." if table.size > MAX_ROWS + 1
    end
    raise Invalid, "The file has no rows." if table.empty?

    header = table.shift.last
    @ignored_columns = [ header.size - MAX_COLUMNS, 0 ].max
    @headers = header.first(MAX_COLUMNS).each_with_index.map { |name, index| name.first(100).presence || "Column #{index + 1}" }
    raise Invalid, "The file has a header row but no clients under it." if table.empty?

    @line_numbers = table.map(&:first)
    @rows = table.map { |_, row| row.first(@headers.size).then { _1.fill("", _1.size...@headers.size) } }
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

  # The separator used most in the header line, outside quoted names.
  def separator(text)
    header = text.each_line.find { _1.strip.present? }.to_s.gsub(/"[^"]*"/, "")
    [ ",", ";", "\t" ].max_by { header.count(_1) }
  end
end
