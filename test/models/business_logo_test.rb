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

  test "other file types are refused" do
    assert_not @business.update(logo: upload("logo.gif"))
    assert_includes @business.errors[:logo], "must be a PNG, JPEG or WebP image"
    disguised = upload("logo.png", io: StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'/>"), content_type: "image/png")
    assert_not @business.reload.update(logo: disguised), "content type comes from the bytes, not the claim"
  end

  test "large files are refused" do
    big = StringIO.new(file_fixture("logo.png").binread + ("\0" * (Business::LOGO_MAX_BYTES + 1)))
    assert_not @business.update(logo: upload("big.png", io: big))
    assert_includes @business.errors[:logo], "must be smaller than 5 MB"
    assert_not @business.reload.logo.attached?
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
