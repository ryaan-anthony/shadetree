require "test_helper"

# Photo and logo cleaning applies the EXIF orientation before stripping metadata, so a phone's
# sideways-stored portrait photo comes out upright. rotated-6.jpg is 40 × 20, grey with a red
# 10 × 10 block in the top-left corner, tagged Orientation=6 ("rotate 90° clockwise to view").
class LogoUploadTest < ActiveSupport::TestCase
  def clean(bytes, name = "photo.jpg") = LogoUpload.clean_photo({ io: StringIO.new(bytes), filename: name }, max_bytes: 1.megabyte)

  def decode(result) = Vips::Image.new_from_buffer(result.attachable[:io].read, "")

  def red?(image, x, y)
    r, g, b = image.getpoint(x, y)
    r > 200 && g < 60 && b < 60
  end

  test "an Orientation=6 photo is turned upright and its orientation tag is gone" do
    original = Vips::Image.new_from_file(file_fixture("rotated-6.jpg").to_s)
    assert_equal [ 40, 20, 6 ], [ original.width, original.height, original.get("orientation") ]

    image = decode(clean(file_fixture("rotated-6.jpg").binread))
    assert_equal [ 20, 40 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
    assert_not_includes image.get_fields, "exif-data"
    assert red?(image, 15, 3), "the top-left corner should now be top-right"
    assert_not red?(image, 3, 3)
  end

  test "an Orientation=8 photo is turned the other way" do
    tagged = Vips::Image.new_from_file(file_fixture("rotated-6.jpg").to_s).mutate { _1.set_type!(GObject::GINT_TYPE, "orientation", 8) }
    image = decode(clean(tagged.write_to_buffer(".jpg")))
    assert_equal [ 20, 40 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
    assert red?(image, 3, 36), "the top-left corner should now be bottom-left"
  end

  test "an Orientation=1 photo keeps its size and pixels" do
    upright = Vips::Image.new_from_file(file_fixture("rotated-6.jpg").to_s).mutate { _1.set_type!(GObject::GINT_TYPE, "orientation", 1) }
    image = decode(clean(upright.write_to_buffer(".jpg")))
    assert_equal [ 40, 20 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
    assert red?(image, 3, 3)
    assert_not red?(image, 35, 3)
  end

  test "logos get the same treatment" do
    result = LogoUpload.prepare({ io: StringIO.new(file_fixture("rotated-6.jpg").binread), filename: "logo.jpg" })
    image = decode(result)
    assert_equal [ 20, 40 ], [ image.width, image.height ]
    assert_not_includes image.get_fields, "orientation"
  end
end
