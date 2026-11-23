# Turns an uploaded logo into something safe to store (CAT-02): it must decode as a PNG,
# JPEG or WebP image (checked by decoding, not by name or claimed type), no larger than
# MAX_BYTES or MAX_SIDE pixels a side (read from the header before anything is decoded),
# and it's re-encoded with all metadata (EXIF, GPS) stripped, so the stored original is
# clean too. Before that, the EXIF orientation is applied to the pixels (phones store
# portrait photos sideways and tag them) and colours are converted to sRGB from any
# embedded profile (iPhones shoot Display P3), because both the tag and the profile go.
# Only real file uploads are accepted, never a signed blob id.
class LogoUpload
  MAX_BYTES = 5.megabytes
  MAX_SIDE = 4_000
  MIN_SIDE = 16
  # The refusals the upload field (f.file_drop) also shows before saving, word for word (PLT-22).
  TYPE_ERROR = "must be a PNG, JPEG or WebP image".freeze
  def self.size_error(max_bytes = MAX_BYTES) = "must be smaller than #{ActiveSupport::NumberHelper.number_to_human_size(max_bytes)}"

  # Photos attached to quotes (QTE-01) go through the same cleaning with roomier limits.
  def self.clean_photo(input, max_bytes:, max_side: 8_000) = prepare(input, max_bytes:, max_side:, min_side: 1)
  FORMATS = {
    "pngload_buffer" => [ "image/png", ".png", {} ],
    "jpegload_buffer" => [ "image/jpeg", ".jpg", { Q: 92 } ],
    "webpload_buffer" => [ "image/webp", ".webp", { Q: 92 } ]
  }.freeze

  # Image fields kept on re-encode; everything else (EXIF, XMP, IPTC, PNG text chunks, GPS,
  # the ICC profile) is removed explicitly, because libvips' strip/keep options don't drop
  # PNG comments.
  KEEP_FIELDS = %w[width height bands format coding interpretation xoffset yoffset xres yres].freeze

  Result = Data.define(:attachable, :error)
  NOTHING = Result.new(attachable: nil, error: nil)

  def self.prepare(input, max_bytes: MAX_BYTES, max_side: MAX_SIDE, min_side: MIN_SIDE)
    return NOTHING if input.blank?

    io, filename = source(input)
    return failure("must be an uploaded image file") unless io
    return failure(size_error(max_bytes)) if io.size > max_bytes

    data = io.read.tap { io.rewind if io.respond_to?(:rewind) }
    image = Vips::Image.new_from_buffer(data, "", access: :sequential)
    content_type, extension, options = FORMATS[image.get("vips-loader")]
    return failure(TYPE_ERROR) unless content_type
    return failure("must be at most #{max_side} × #{max_side} pixels") if image.width > max_side || image.height > max_side
    return failure("must be at least #{min_side} pixels on each side") if image.width < min_side || image.height < min_side

    clean = without_metadata(upright_srgb(image, data)).write_to_buffer(extension, strip: true, **options)
    name = "#{File.basename(filename.to_s, ".*").presence || "logo"}#{extension}"
    Result.new(attachable: { io: StringIO.new(clean), filename: name, content_type: }, error: nil)
  rescue Vips::Error
    failure(TYPE_ERROR)
  end

  def self.source(input)
    case input
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile then [ input.tempfile, input.original_filename ]
    when Hash then input[:io] && [ input[:io], input[:filename] ]
    end
  end

  # Rotating needs random access, which decodes the whole image first (8000 × 6000 is about
  # 150 MB, which libvips puts in a temp file because it's over its 100 MB disc threshold), so
  # only images that need turning are reopened that way; the rest stay sequential (streamed).
  def self.upright_srgb(image, data)
    if image.get_fields.include?("orientation") && ![ 0, 1 ].include?(image.get("orientation"))
      image = Vips::Image.new_from_buffer(data, "", access: :random).autorot
    end
    return image unless image.get_fields.include?("icc-profile-data")

    begin
      image.icc_transform("srgb", embedded: true)
    rescue Vips::Error
      image # an unreadable profile: keep the pixels as they are rather than refuse the photo
    end
  end

  def self.without_metadata(image)
    image.mutate { |copy| (image.get_fields - KEEP_FIELDS).each { copy.remove!(_1) } }
  end

  def self.failure(message) = Result.new(attachable: nil, error: message)
end
