require "test_helper"

# CAT-02: logo uploads.
class BusinessLogoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup { @business = businesses(:one) }

  def upload(name, io: nil, content_type: nil)
    io ||= file_fixture(name).open
    { io:, filename: name, content_type: content_type || Marcel::MimeType.for(io, name:) }
  end

  test "a PNG is accepted and sized for web, email and PDF" do
    assert @business.update(logo: upload("logo.png"))
    assert @business.reload.logo.attached?
    branding = @business.branding
    assert branding.logo?
    %i[web email pdf].each { assert_kind_of ActiveStorage::VariantWithRecord, branding.logo(_1) }
    image = Vips::Image.new_from_buffer(branding.logo(:pdf).processed.download, "")
    assert_operator image.width, :<=, 960
  end

  test "files that don't decode as PNG, JPEG or WebP are refused, whatever their name or claimed type" do
    assert_not @business.update(logo: upload("logo.gif"))
    assert_includes @business.errors[:logo], "must be a PNG, JPEG or WebP image"
    [ "\n <svg xmlns='http://www.w3.org/2000/svg'/>", "not an image at all" ].each do |bytes|
      assert_not @business.reload.update(logo: upload("logo.png", io: StringIO.new(bytes), content_type: "image/png")), bytes
      assert_includes @business.errors[:logo], "must be a PNG, JPEG or WebP image"
    end
    assert_not @business.reload.logo.attached?
  end

  test "large files and huge or tiny dimensions are refused before decoding" do
    big = StringIO.new(file_fixture("logo.png").binread + ("\0" * (Business::LOGO_MAX_BYTES + 1)))
    assert_not @business.update(logo: upload("big.png", io: big))
    assert_includes @business.errors[:logo], "must be smaller than 5 MB"

    wide = Vips::Image.black(LogoUpload::MAX_SIDE + 1, 20).write_to_buffer(".png")
    assert_not @business.reload.update(logo: upload("wide.png", io: StringIO.new(wide)))
    assert_includes @business.errors[:logo], "must be at most 4000 × 4000 pixels"

    tiny = Vips::Image.black(8, 8).write_to_buffer(".png")
    assert_not @business.reload.update(logo: upload("tiny.png", io: StringIO.new(tiny)))
    assert_includes @business.errors[:logo], "must be at least 16 pixels on each side"
    assert_not @business.reload.logo.attached?
  end

  test "the stored original has its metadata stripped" do
    tagged = Vips::Image.new_from_file(file_fixture("logo.png").to_s).mutate { _1.set_type!(GObject::GSTR_TYPE, "png-comment-0-location", "40.7,-74.0") }
    bytes = tagged.write_to_buffer(".png")
    assert_includes Vips::Image.new_from_buffer(bytes, "").get_fields, "png-comment-0-location"

    @business.update!(logo: upload("tagged.png", io: StringIO.new(bytes)))
    stored = Vips::Image.new_from_buffer(@business.reload.logo.download, "")
    assert_not_includes stored.get_fields, "png-comment-0-location"
    assert_equal "image/png", @business.logo.content_type
  end

  test "a signed blob id is not an upload, so another business's logo can't be attached" do
    other = businesses(:two)
    other.update!(logo: upload("logo.png"))
    assert_not @business.update(logo: other.logo.blob.signed_id)
    assert_includes @business.errors[:logo], "must be an uploaded image file"
    assert_not @business.reload.logo.attached?
  end

  test "a blank file field changes nothing" do
    @business.update!(logo: upload("logo.png"))
    assert @business.update(logo: "", brand_color: "#9a3412")
    assert @business.reload.logo.attached?
  end

  test "remove_logo removes it; a new upload wins over remove" do
    @business.update!(logo: upload("logo.png"))
    @business.update!(remove_logo: "1", logo: upload("logo.png"))
    assert @business.reload.logo.attached?
    perform_enqueued_jobs { @business.update!(remove_logo: "1") }
    assert_not @business.reload.logo.attached?
  end

  test "brand color accepts a hex without the hash and lowercases it" do
    @business.update!(brand_color: "9A3412")
    assert_equal "#9a3412", @business.brand_color
    assert_not @business.update(brand_color: "orange")
    assert_includes @business.errors[:brand_color], "should be a color like #047857"
  end
end
