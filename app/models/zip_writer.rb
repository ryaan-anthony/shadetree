# A small ZIP archive writer on the standard library (INS-02 full exports), so building one
# needs no extra gem. Entries are added one at a time and written straight to the IO; text is
# deflated, files that are already compressed (PDFs, photos) are stored as they are. Names are
# UTF-8. No ZIP64: an archive must stay under 4 GB and 65,535 entries (the export caps its size
# well below that).
#
#   File.open("export.zip", "wb") do |file|
#     ZipWriter.open(file) do |zip|
#       zip.add("csv/clients.csv", csv_text)
#       zip.add("files/photo.jpg", jpeg_bytes, compress: false)
#     end
#   end
class ZipWriter
  class TooLarge < StandardError; end

  LIMIT = 0xFFFF_FFFF
  Entry = Data.define(:name, :method, :crc, :compressed_size, :size, :offset, :time, :date)

  def self.open(io)
    zip = new(io)
    yield zip
    zip.finish
  end

  def initialize(io)
    @io = io
    @entries = []
    @offset = 0
    @names = Set.new
  end

  def size = @offset

  def add(name, data, compress: true, at: Time.current)
    name = unique_name(name.to_s.unicode_normalize.delete_prefix("/"))
    data = data.to_s.b
    body = compress ? deflate(data) : data
    method = compress ? 8 : 0
    raise TooLarge, "The archive would be larger than 4 GB." if @offset + body.bytesize + 1024 > LIMIT
    raise TooLarge, "The archive would hold more than 65,535 files." if @entries.size >= 0xFFFF

    time, date = dos_time(at)
    entry = Entry.new(name:, method:, crc: Zlib.crc32(data), compressed_size: body.bytesize, size: data.bytesize, offset: @offset, time:, date:)
    write([ 0x04034b50, 20, 0x0800, method, time, date, entry.crc, entry.compressed_size, entry.size, name.bytesize, 0 ].pack("VvvvvvVVVvv"), name.b, body)
    @entries << entry
    entry
  end

  def finish
    directory_offset = @offset
    @entries.each do |e|
      write([ 0x02014b50, 0x031E, 20, 0x0800, e.method, e.time, e.date, e.crc, e.compressed_size, e.size, e.name.bytesize, 0, 0, 0, 0, 0o100644 << 16, e.offset ]
              .pack("VvvvvvvVVVvvvvvVV"), e.name.b)
    end
    write([ 0x06054b50, 0, 0, @entries.size, @entries.size, @offset - directory_offset, directory_offset, 0 ].pack("VvvvvVVv"))
    @io
  end

  private

  def write(*parts)
    parts.each do |part|
      @io.write(part)
      @offset += part.bytesize
    end
  end

  def deflate(data)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflater.deflate(data, Zlib::FINISH).tap { deflater.close }
  end

  # Two files can't share a name: "photo.jpg", then "photo (2).jpg".
  def unique_name(name)
    candidate, number = name, 1
    while @names.include?(candidate.downcase) # "Dup.jpg" and "dup.jpg" collide on Mac and Windows
      number += 1
      candidate = name.sub(/(\.[^.\/]+)?\z/) { " (#{number})#{_1}" }
    end
    @names << candidate.downcase
    candidate
  end

  def dos_time(at)
    at = at.to_time
    [ (at.hour << 11) | (at.min << 5) | (at.sec / 2), ((at.year - 1980).clamp(0, 127) << 9) | (at.month << 5) | at.day ]
  end
end
