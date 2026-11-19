require "test_helper"

# INS-02: the full-account export: built in the background, a link that expires.
class Admin::FullExportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  # Names and contents of a zip, read with Ruby's standard library only.
  def unzip(data)
    entries = {}
    offset = 0
    while data.byteslice(offset, 4) == [ 0x04034b50 ].pack("V")
      _, _, _, method, _, _, _, compressed, _, name_length, extra = data.byteslice(offset, 30).unpack("VvvvvvVVVvv")
      name = data.byteslice(offset + 30, name_length).force_encoding("UTF-8")
      body = data.byteslice(offset + 30 + name_length + extra, compressed)
      entries[name] = method == 8 ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(body) : body
      offset += 30 + name_length + extra + compressed
    end
    entries
  end

  test "everything in one zip: spreadsheets, PDFs, files and photos, with a readme; the requester is told" do
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.create!(client:, created_by: @owner, title: "Spring cleanup")
      quote.attachments.attach(io: StringIO.new("%PDF-1.4 plan\n%%EOF\n"), filename: "plan.pdf", content_type: "application/pdf")
      job = Job.create!(client:, title: "Mowing")
      visit = job.visits.new(scheduled_on: Date.new(2026, 11, 20), timing: "anytime", duration_minutes: 60).tap { _1.schedule!(by: @owner) }
      visit.photos.attach(io: StringIO.new("jpegdata"), filename: "yard.jpg", content_type: "image/jpeg")
    end
    as_business(businesses(:two)) { Client.create!(display_name: "Their client", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]) }

    assert_enqueued_with(job: DataExportJob) { post admin_data_exports_path }
    post admin_data_exports_path
    assert_equal 1, as_business(@business) { DataExport.where(kind: "full").count }, "one at a time"
    get admin_data_exports_path
    assert_select "#full-export", /Being put together/

    with_fake_pdf_renderer { perform_enqueued_jobs(only: DataExportJob) }
    export = as_business(@business) { DataExport.find_by!(kind: "full") }
    assert export.downloadable?
    notification = as_business(@business) { Notification.find_by!(kind: "data_export_ready") }
    assert_equal @owner.id, notification.user_id

    get admin_data_exports_path
    assert_select "#full-export a[href=?]", admin_data_export_path(export), "Download the zip"
    get admin_data_export_path(export)
    assert_equal "application/zip", response.media_type
    files = unzip(response.body)
    assert_includes files.keys, "csv/clients.csv"
    assert_includes files.keys, "README.txt"
    assert(files.keys.any? { _1.start_with?("documents/quotes/") && _1.end_with?(".pdf") })
    assert_includes files.keys, "files/quotes/#{as_business(@business) { Quote.last.number }}/plan.pdf"
    assert(files.keys.any? { _1.start_with?("files/visits/") && _1.end_with?("yard.jpg") })
    assert_equal "jpegdata", files.find { _1.first.end_with?("yard.jpg") }.last
    assert_match "Maria Lopez", files["csv/clients.csv"]
    assert_no_match(/Their client/, files.values.join)
  end

  test "the link expires; then the zip is removed and a new one can be made" do
    export = as_business(@business) do
      DataExport.create!(kind: "full", status: "ready", requested_by: @owner, expires_at: 1.day.from_now,
                         file: { io: StringIO.new("PK"), filename: "x.zip", content_type: "application/zip" })
    end
    travel 2.days do
      get admin_data_export_path(export)
      assert_redirected_to admin_data_exports_path
      assert_match "expired", flash[:alert]
      PruneDataExportsJob.perform_now
      assert_equal "expired", as_business(@business) { export.reload.status }
    end
  end

  test "a failed build says why" do
    post admin_data_exports_path
    original = DataExport::Archive.instance_method(:write)
    DataExport::Archive.define_method(:write) { |_io| raise DataExport::Archive::TooLarge, "Your data is larger than 2 GB, too big for one download." }
    perform_enqueued_jobs(only: DataExportJob)
    assert_equal "failed", as_business(@business) { DataExport.find_by!(kind: "full").status }
    assert_match "larger than 2 GB", as_business(@business) { Notification.find_by!(kind: "data_export_ready").title }
  ensure
    DataExport::Archive.define_method(:write, original)
  end

  test "another business's export isn't found" do
    theirs = as_business(businesses(:two)) { DataExport.create!(kind: "full", status: "ready", expires_at: 1.day.from_now) }
    assert_not_found_across_businesses { get admin_data_export_path(theirs) }
  end
end
