require "test_helper"

# Photo and logo cleaning (LogoUpload): the EXIF orientation is applied and colours are
# converted to sRGB before the metadata is stripped, so a phone's sideways-stored portrait photo
# comes out upright and a Display P3 photo keeps its colours. rotated-6.jpg is 40 × 20, grey with
# a red 10 × 10 block in the top-left corner, tagged Orientation=6 ("rotate 90° clockwise").
class LogoUploadTest < ActiveSupport::TestCase
  # Where the stored top-left corner ends up once each orientation is applied.
  CORNERS = { 1 => :top_left, 2 => :top_right, 3 => :bottom_right, 4 => :bottom_left,
              5 => :top_left, 6 => :top_right, 7 => :bottom_right, 8 => :bottom_left }.freeze

  def clean(bytes, name = "photo.jpg") = LogoUpload.clean_photo({ io: StringIO.new(bytes), filename: name }, max_bytes: 5.megabytes)

  def decode(result)
    assert_nil result.error
    Vips::Image.new_from_buffer(result.attachable[:io].read, "")
  end

  def fixture = Vips::Image.new_from_file(file_fixture("rotated-6.jpg").to_s)

  def tagged(image, orientation) = image.mutate { _1.set_type!(GObject::GINT_TYPE, "orientation", orientation) }

  def red_corners(image)
    { top_left: [ 3, 3 ], top_right: [ image.width - 4, 3 ], bottom_left: [ 3, image.height - 4 ],
      bottom_right: [ image.width - 4, image.height - 4 ] }.select do |_, (x, y)|
      r, g, b = image.getpoint(x, y)
      r > 200 && g < 60 && b < 60
    end.keys
  end

  test "the Orientation=6 fixture is turned upright and its orientation tag is gone" do
    assert_equal [ 40, 20, 6 ], [ fixture.width, fixture.height, fixture.get("orientation") ]

    image = decode(clean(file_fixture("rotated-6.jpg").binread))
    assert_equal [ 20, 40 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
    assert_not_includes image.get_fields, "exif-data"
    assert_equal [ :top_right ], red_corners(image)
  end

  test "every orientation, 1 to 8, is applied to the pixels" do
    CORNERS.each do |orientation, corner|
      image = decode(clean(tagged(fixture, orientation).write_to_buffer(".jpg")))
      size = orientation >= 5 ? [ 20, 40 ] : [ 40, 20 ]
      assert_equal size, [ image.width, image.height ], "orientation #{orientation}"
      assert_equal [ corner ], red_corners(image), "orientation #{orientation}"
      assert_not_includes image.get_fields, "orientation"
    end
  end

  test "a phone-sized Orientation=6 photo is accepted and turned" do
    photo = (Vips::Image.black(1200, 900) + [ 128, 128, 128 ]).cast(:uchar).copy(interpretation: :srgb)
    photo = photo.draw_rect([ 255, 0, 0 ], 0, 0, 100, 100, fill: true)
    image = decode(clean(tagged(photo, 6).write_to_buffer(".jpg", Q: 85)))
    assert_equal [ 900, 1200 ], [ image.width, image.height ]
    assert_equal [ :top_right ], red_corners(image)
  end

  test "an embedded colour profile is converted to sRGB, then stripped" do
    srgb_red = (Vips::Image.black(32, 32) + [ 255, 0, 0 ]).cast(:uchar).copy(interpretation: :srgb)
    p3 = srgb_red.icc_transform("p3", input_profile: "srgb")
    assert_includes p3.get_fields, "icc-profile-data"
    assert_operator p3.getpoint(5, 5)[1], :>, 30, "the same red written in P3 values"

    image = decode(clean(p3.write_to_buffer(".jpg", Q: 95)))
    assert_not_includes image.get_fields, "icc-profile-data"
    r, g, b = image.getpoint(5, 5)
    assert_operator r, :>, 245
    assert_operator g + b, :<, 15
  end

  test "logos get the same treatment" do
    image = decode(LogoUpload.prepare({ io: StringIO.new(file_fixture("rotated-6.jpg").binread), filename: "logo.jpg" }))
    assert_equal [ 20, 40 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
  end

  test "photos take a minimum size when one is given (ACC-09's 128 px); by default any size goes" do
    small = file_fixture("rotated-6.jpg").binread
    assert_nil clean(small).error
    result = LogoUpload.clean_photo({ io: StringIO.new(small), filename: "face.jpg" }, max_bytes: 5.megabytes, min_side: 128)
    assert_equal "must be at least 128 pixels on each side", result.error
  end
end
