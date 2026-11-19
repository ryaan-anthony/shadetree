require "test_helper"

class ZipWriterTest < ActiveSupport::TestCase
  test "names are unique ignoring case, entries check out, and files keep their own dates" do
    io = StringIO.new(+"", "wb")
    ZipWriter.open(io) do |zip|
      zip.add("a/photo.jpg", "1", compress: false)
      zip.add("a/Photo.jpg", "2", compress: false)
      zip.add("csv/x.csv", "Name\n" * 50, at: Time.utc(2025, 6, 7, 8, 9, 10))
    end
    data = io.string
    names = []
    offset = 0
    while data.byteslice(offset, 4) == [ 0x04034b50 ].pack("V")
      _, _, flags, method, time, date, crc, compressed, size, name_length = data.byteslice(offset, 30).unpack("VvvvvvVVVv")
      name = data.byteslice(offset + 30, name_length)
      body = data.byteslice(offset + 30 + name_length, compressed)
      plain = method == 8 ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(body) : body
      assert_equal 0x0800, flags & 0x0800, "UTF-8 names"
      assert_equal [ crc, size ], [ Zlib.crc32(plain), plain.bytesize ]
      if name == "csv/x.csv"
        assert_equal [ 2025, 6, 7 ], [ (date >> 9) + 1980, (date >> 5) & 15, date & 31 ]
        assert_equal [ 8, 9, 10 ], [ time >> 11, (time >> 5) & 63, (time & 31) * 2 ]
      end
      names << name
      offset += 30 + name_length + compressed
    end
    assert_equal [ "a/photo.jpg", "a/Photo (2).jpg", "csv/x.csv" ], names
    assert_equal [ 0x06054b50, 3 ], data.byteslice(-22, 22).unpack("VvvvvVVv").values_at(0, 3)
  end

  test "odd names are made safe" do
    archive = DataExport::Archive.new(businesses(:one))
    assert_equal [ "file", "file", "hidden", "report-2026.pdf", "#{"x" * 110}.jpeg" ],
                 [ "..", ".", ".hidden", "report/2026.pdf", "#{"x" * 200}.jpeg" ].map { archive.send(:safe, _1) }
  end
end
