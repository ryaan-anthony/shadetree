require "test_helper"

# PLT-09: what the restore drill checks in a restored database and storage.
class RestoreCheckTest < ActiveSupport::TestCase
  test "passes when the restore holds what the backup counted and every upload" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("photo bytes"), filename: "photo.jpg")
    counts = RestoreCheck.counts

    result = RestoreCheck.new(expected: counts.transform_values(&:to_s)).call

    assert result.ok, result.lines.join("\n")
    assert_includes result.lines, "ok   active_storage_blobs: #{counts["active_storage_blobs"]} (the backup counted #{counts["active_storage_blobs"]})"
    assert result.lines.any? { _1.start_with?("ok   files:") }
    blob.purge
  end

  test "fails when rows the backup counted are missing" do
    result = RestoreCheck.new(expected: { "businesses" => RestoreCheck.counts["businesses"] + 1 }).call

    assert_not result.ok
    assert_equal 1, result.failures.size
    assert_match(/\Abusinesses: \d+ \(the backup counted \d+\)\z/, result.failures.first)
  end

  test "fails when an upload's file is missing or has another size" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("photo bytes"), filename: "photo.jpg")
    File.write(ActiveStorage::Blob.service.path_for(blob.key), "cut")

    result = RestoreCheck.new.call

    assert_not result.ok
    assert(result.failures.any? { _1.start_with?("files:") })
    blob.purge
  end
end
