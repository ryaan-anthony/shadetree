require "test_helper"

# ACC-09: a member's profile in a business: photo (cleaned like every photo), title, bio and
# work phone; what clients may see of it; and what deleting an account or business removes.
class TeamProfileTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @member = business_users(:one) }

  def photo(width = 300, height = 200, format: ".jpg", **options)
    image = (Vips::Image.black(width, height) + [ 90, 140, 90 ]).cast(:uchar).copy(interpretation: :srgb)
    image = image.mutate { _1.set_type!(GObject::GSTR_TYPE, "exif-ifd0-Artist", "Somebody") } if format == ".jpg"
    file = Tempfile.new([ "face", format ], binmode: true)
    file.write(image.write_to_buffer(format, **options))
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: "IMG_2041#{format}")
  end

  test "the fields are optional and limited: title 40, bio 200, a dialable work phone" do
    assert @member.update(title: nil, bio: nil, work_phone: nil)
    @member.assign_attributes(title: "x" * 41, bio: "y" * 201, work_phone: "12")
    assert_not @member.valid?
    assert @member.errors.of_kind?(:title, :too_long)
    assert @member.errors.of_kind?(:bio, :too_long)
    assert_equal [ "needs 7 to 15 digits" ], @member.errors[:work_phone]

    assert @member.update(title: "  Lead   technician ", bio: "Ten years on mowers.\r\nAsk me about hedges.", work_phone: "(555) 010-2200")
    assert_equal [ "Lead technician", "Ten years on mowers.\nAsk me about hedges." ], [ @member.title, @member.bio ]
  end

  test "the database refuses an over-long title or bio" do
    assert_raises(ActiveRecord::StatementInvalid) { @member.update_columns(title: "x" * 41) }
  end

  test "a photo is cleaned: re-encoded without its metadata, and a square is cut from the centre" do
    assert @member.update(photo: photo)
    stored = Vips::Image.new_from_buffer(@member.photo.download, "")
    assert_equal [ 300, 200 ], [ stored.width, stored.height ]
    assert_empty stored.get_fields.grep(/exif|orientation|icc/)
    assert_equal "IMG_2041.jpg", @member.photo.filename.to_s
    thumb = Vips::Image.new_from_buffer(@member.photo.variant(:thumb).processed.download, "")
    assert_equal [ 96, 96 ], [ thumb.width, thumb.height ]
  end

  test "photos must be 128 px to 8,000 px a side, 10 MB at most, and a real image" do
    assert_not @member.update(photo: photo(127, 400))
    assert_equal [ "must be at least 128 pixels on each side" ], @member.errors[:photo]
    assert_not @member.update(photo: photo(8_001, 130, format: ".png"))
    assert_equal [ "must be at most 8000 × 8000 pixels" ], @member.errors[:photo]
    assert_not @member.update(photo: Rack::Test::UploadedFile.new(StringIO.new("not an image"), "image/jpeg", original_filename: "x.jpg"))
    assert_equal [ "must be a PNG, JPEG or WebP photo" ], @member.errors[:photo]
    assert_equal 10.megabytes, TeamProfile::PHOTO_MAX_BYTES
    assert_not @member.reload.photo.attached?

    assert @member.update(photo: photo(128, 128, format: ".webp"))
    assert_equal "image/webp", @member.photo.content_type
  end

  test "a rejected photo keeps the one there; Remove takes it off" do
    @member.update!(photo: photo)
    blob = @member.photo.blob
    assert_not @member.update(photo: photo(20, 20))
    assert_equal blob, @member.reload.photo.blob

    assert_equal [ "photo", "title" ], @member.tap { _1.assign_attributes(remove_photo: "1", title: "Crew lead") }.profile_changes
    perform_enqueued_jobs { @member.save! }
    assert_not @member.reload.photo.attached?
  end

  test "clients get the first name only, never the full name or email, and the work phone or the business's" do
    user = @member.user
    assert_equal [ "John", "J" ], [ @member.client_first_name, @member.client_initial ]
    user.update_columns(first_name: " ")
    assert_nil @member.reload.client_first_name
    assert_nil @member.client_initial

    business = @member.business
    business.update_columns(phone: "(555) 300-1000")
    assert_equal "(555) 300-1000", @member.client_phone(business)
    @member.update!(work_phone: "555-010-2200")
    assert_equal "555-010-2200", @member.client_phone(business)
    business.update_columns(phone: nil)
    @member.update!(work_phone: nil)
    assert_nil @member.client_phone(business)
  end

  test "deleting an account removes the photo and its sizes and clears the profile in every business" do
    user = users(:one)
    other = business_users(:one_member_of_two)
    [ @member, other ].each { _1.update!(photo: photo, title: "Tech", bio: "Hi", work_phone: "555-010-2200") }
    @member.photo.variant(:thumb).processed
    blob_ids = [ @member, other ].map { _1.photo.blob.id }
    variant_blob = ActiveStorage::VariantRecord.find_by!(blob_id: blob_ids.first).image.blob
    business_users(:one).business.business_users.create!(user: users(:two), role: "owner") # so the business isn't blocking

    perform_enqueued_jobs(only: PurgeDeletedFilesJob) { assert user.delete_account! }

    [ @member, other ].each do |membership|
      membership.reload
      assert_not membership.photo.attached?
      assert_equal [ nil, nil, nil ], [ membership.title, membership.bio, membership.work_phone ]
    end
    (blob_ids + [ variant_blob.id ]).each { assert_not ActiveStorage::Blob.exists?(_1) }
    assert_not variant_blob.service.exist?(variant_blob.key), "the size's file is gone too"
  end

  test "deleting a business removes its members' photos" do
    @member.update!(photo: photo)
    blob = @member.photo.blob
    ProfileEvent.record!(@member, %w[photo], by: users(:two))
    blob_ids = BusinessDeletion.run!(@member.business)
    assert_includes blob_ids, blob.id
    BusinessDeletion.purge_blobs(blob_ids)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ProfileEvent.unscoped.exists?(business_user_id: @member.id)
  end

  test "a change records which fields, never their values" do
    event = ProfileEvent.record!(@member, %w[photo work_phone], by: users(:two))
    assert_equal "photo and work phone", event.summary
    assert_equal({ "changed" => %w[photo work_phone] }, event.data)
    assert_raises(ActiveRecord::RecordInvalid) { ProfileEvent.record!(@member, %w[email], by: nil) }
  end
end
