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

  # Names and contents of a zip, read with Ruby's standard library only; the central directory
  # must list the same names.
  def unzip(data)
    eocd = data.rindex([ 0x06054b50 ].pack("V"))
    count, _, directory_offset = data.byteslice(eocd + 10, 10).unpack("vVV")
    listed = []
    offset = directory_offset
    count.times do
      name_length, extra, comment = data.byteslice(offset + 28, 6).unpack("vvv")
      listed << data.byteslice(offset + 46, name_length).force_encoding("UTF-8")
      offset += 46 + name_length + extra + comment
    end
    entries = local_entries(data)
    assert_equal listed, entries.keys, "central directory matches the entries"
    entries
  end

  def local_entries(data)
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
    assert_select "#full-export a[href=?]", admin_data_export_path(export, part: 1), "Download the zip"
    get admin_data_export_path(export, part: 1)
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
    assert_match "Not in this export", files["README.txt"]
    assert as_business(@business) { DataExport.exists?(kind: "full_download", requested_by: @owner) }, "downloads are logged"
  end

  test "a big export comes in parts; another Admin's download is logged" do
    as_business(@business) do
      job = Job.create!(client: Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ]), title: "Mowing")
      3.times { |i| job.attachments.attach(io: StringIO.new(Random.bytes(3_000)), filename: "photo#{i}.jpg", content_type: "image/jpeg") }
    end
    part_bytes = DataExport::Archive::PART_BYTES
    DataExport::Archive.send(:remove_const, :PART_BYTES)
    DataExport::Archive.const_set(:PART_BYTES, 4_000)
    post admin_data_exports_path
    with_fake_pdf_renderer { perform_enqueued_jobs(only: DataExportJob) }
    export = as_business(@business) { DataExport.find_by!(kind: "full") }
    assert_operator export.parts.size, :>, 1
    admin = member_with_role("admin")
    sign_out :user
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_data_exports_path
    assert_select "#full-export a", /Download part 1 of #{export.parts.size}/
    names = export.parts.size.times.flat_map do |index|
      get admin_data_export_path(export, part: index + 1)
      unzip(response.body).keys
    end
    assert_equal 3, names.count { _1.start_with?("files/jobs/") }
    assert_equal 1, names.count("README.txt"), "the README is in the last part"
    assert as_business(@business) { DataExport.exists?(kind: "full_download", requested_by: admin) }
  ensure
    DataExport::Archive.send(:remove_const, :PART_BYTES)
    DataExport::Archive.const_set(:PART_BYTES, part_bytes)
  end

  test "a build that stopped (a deploy) doesn't block a new one" do
    stuck = as_business(@business) { DataExport.create!(kind: "full", status: "building", requested_by: @owner) }
    stuck.update_columns(updated_at: 2.hours.ago)
    get admin_data_exports_path
    assert_select "#full-export-failed", /stopped partway/
    assert_enqueued_with(job: DataExportJob) { post admin_data_exports_path }
    assert_equal "failed", as_business(@business) { stuck.reload.status }
  end

  test "the link expires; then the zip is removed and a new one can be made" do
    export = as_business(@business) do
      DataExport.create!(kind: "full", status: "ready", requested_by: @owner, expires_at: 1.day.from_now,
                         files: [ { io: StringIO.new("PK"), filename: "x.zip", content_type: "application/zip" } ])
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
    original = DataExport::Archive.instance_method(:write_parts)
    DataExport::Archive.define_method(:write_parts) { raise DataExport::Archive::TooLarge, "Your files add up to more than 25 GB." }
    perform_enqueued_jobs(only: DataExportJob)
    assert_equal "failed", as_business(@business) { DataExport.find_by!(kind: "full").status }
    assert_match "more than 25 GB", as_business(@business) { Notification.find_by!(kind: "data_export_ready").title }
    get admin_data_exports_path
    assert_select "#full-export-failed", /more than 25 GB/
  ensure
    DataExport::Archive.define_method(:write_parts, original)
  end

  test "another business's export isn't found" do
    theirs = as_business(businesses(:two)) { DataExport.create!(kind: "full", status: "ready", expires_at: 1.day.from_now) }
    assert_not_found_across_businesses { get admin_data_export_path(theirs) }
  end
end
