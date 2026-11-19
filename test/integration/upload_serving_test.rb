require "test_helper"

# PLT-13: stored files are served so nothing in them runs on our origin. Uploads themselves are
# checked by content and re-encoded without metadata (LogoUpload, DocumentAttachments; their
# own tests); this covers what happens when a file is fetched.
class UploadServingTest < ActionDispatch::IntegrationTest
  def fetch(blob, disposition: nil)
    get rails_blob_path(blob, disposition:)
    follow_redirect!
    response
  end

  test "risky types are downloads, served as plain bytes, never rendered" do
    { "page.html" => "text/html", "drawing.svg" => "image/svg+xml", "script.js" => "text/javascript", "style.css" => "text/css" }.each do |name, type|
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("<script>alert(1)</script>"), filename: name, content_type: type, identify: false)
      fetch(blob, disposition: "inline")
      assert_match(/\Aattachment/, response.headers["Content-Disposition"], name)
      assert_equal "application/octet-stream", response.media_type, name
      assert_equal "nosniff", response.headers["X-Content-Type-Options"], name
    end
  end

  test "photos and PDFs open in the browser, with the content type they really have" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF\n"), filename: "plan.pdf")
    fetch(blob, disposition: "inline")
    assert_equal "application/pdf", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
  end

  test "blobs can't be created from outside the app's own forms" do
    post rails_direct_uploads_path, params: { blob: { filename: "x.html", byte_size: 10, checksum: "x", content_type: "text/html" } }
    assert_response :not_found
  end
end
