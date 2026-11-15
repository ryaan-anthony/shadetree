# Turns an uploaded logo into something safe to store (CAT-02): it must decode as a PNG,
# JPEG or WebP image (checked by decoding, not by name or claimed type), no larger than
# MAX_BYTES or MAX_SIDE pixels a side (read from the header before anything is decoded),
# and it's re-encoded with all metadata (EXIF, GPS) stripped, so the stored original is
# clean too. Only real file uploads are accepted, never a signed blob id.
class LogoUpload
  MAX_BYTES = 5.megabytes
  MAX_SIDE = 4_000
  MIN_SIDE = 16
  FORMATS = {
    "pngload_buffer" => [ "image/png", ".png", {} ],
    "jpegload_buffer" => [ "image/jpeg", ".jpg", { Q: 92 } ],
    "webpload_buffer" => [ "image/webp", ".webp", { Q: 92 } ]
  }.freeze

  # Image fields kept on re-encode; everything else (EXIF, XMP, IPTC, PNG text chunks, GPS)
  # is removed explicitly, because libvips' strip/keep options don't drop PNG comments.
  KEEP_FIELDS = %w[width height bands format coding interpretation xoffset yoffset xres yres icc-profile-data].freeze

  Result = Data.define(:attachable, :error)
  NOTHING = Result.new(attachable: nil, error: nil)

  def self.prepare(input)
    return NOTHING if input.blank?

    io, filename = source(input)
    return failure("must be an uploaded image file") unless io
    return failure("must be smaller than #{MAX_BYTES / 1.megabyte} MB") if io.size > MAX_BYTES

    data = io.read.tap { io.rewind if io.respond_to?(:rewind) }
    image = Vips::Image.new_from_buffer(data, "", access: :sequential)
    content_type, extension, options = FORMATS[image.get("vips-loader")]
    return failure("must be a PNG, JPEG or WebP image") unless content_type
    return failure("must be at most #{MAX_SIDE} × #{MAX_SIDE} pixels") if image.width > MAX_SIDE || image.height > MAX_SIDE
    return failure("must be at least #{MIN_SIDE} pixels on each side") if image.width < MIN_SIDE || image.height < MIN_SIDE

    clean = without_metadata(image).write_to_buffer(extension, strip: true, **options)
    name = "#{File.basename(filename.to_s, ".*").presence || "logo"}#{extension}"
    Result.new(attachable: { io: StringIO.new(clean), filename: name, content_type: }, error: nil)
  rescue Vips::Error
    failure("must be a PNG, JPEG or WebP image")
  end

  def self.source(input)
    case input
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile then [ input.tempfile, input.original_filename ]
    when Hash then input[:io] && [ input[:io], input[:filename] ]
    end
  end

  def self.without_metadata(image)
    image.mutate { |copy| (image.get_fields - KEEP_FIELDS).each { copy.remove!(_1) } }
  end

  def self.failure(message) = Result.new(attachable: nil, error: message)
end
