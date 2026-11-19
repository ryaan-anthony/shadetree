require "test_helper"

# CLI-06: running an import in the background, its summary, report and undo.
class Admin::ClientImportRunsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  CSV_TEXT = <<~CSV
    Name,Email,Phone,Notes
    Maria Lopez,maria@example.com,,existing client
    Bo Diaz,bo@example.com,555-010-0200,
    Cal,not-an-email,,
    Bo Again,bo@example.com,,same email as Bo
    Eve,eve@example.com,,=HYPERLINK("http://evil.example")
  CSV

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
  end

  def start_import(text = CSV_TEXT, duplicates: "skip")
    post admin_client_imports_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: "list.csv") }
    import = as_business(@business) { ClientImport.last }
    patch admin_client_import_path(import), params: { client_import: { columns: import.mapping, duplicates: }, start: "1" }
    import
  end

  test "an import runs in the background, skips likely duplicates, reports the rest, and tells the person who started it" do
    import = nil
    assert_enqueued_with(job: ClientImportJob) { import = start_import }
    assert_redirected_to admin_client_import_path(import)
    follow_redirect!
    assert_select "progress"
    assert_select "meta[http-equiv=refresh]"

    perform_enqueued_jobs(only: ClientImportJob)
    import = as_business(@business) { import.reload }
    assert_equal [ "finished", 2, 2, 1 ], [ import.status, import.created_count, import.skipped_count, import.failed_count ]
    assert_equal [ "Bo Diaz", "Eve" ], as_business(@business) { import.clients.order(:display_name).pluck(:display_name) }
    assert_not import.file.attached?, "the uploaded file is removed once it's done"
    assert_equal [ 2, 4, 5 ], import.problems.map { _1["row"] }
    assert_match "matches Maria Lopez", import.problems.first["reason"]
    assert_match "isn't an email", import.problems.second["reason"]
    assert_match "matches Bo Diaz", import.problems.third["reason"], "a repeat within the file is a duplicate too"

    notification = as_business(@business) { Notification.find_by!(kind: "client_import_finished") }
    assert_equal [ @owner.id, "Imported 2 clients from list.csv; 2 skipped, 1 couldn't be added." ], [ notification.user_id, notification.title ]

    get admin_client_import_path(import)
    assert_select "meta[http-equiv=refresh]", 0
    assert_select "#import-summary", /Added\s*2.*Skipped\s*2.*Couldn't add\s*1/m
    assert_select "#import-problems li", 3
    get report_admin_client_import_path(import)
    report = CSV.parse(response.body)
    assert_equal [ "Row", "Why", "Name", "Email", "Phone", "Notes" ], report.first
    assert_equal 4, report.size
  end

  test "the report defuses spreadsheet formulas" do
    import = as_business(@business) { ClientImport.create!(filename: "x.csv", headers: [ "Name" ], mapping: { "0" => "display_name" }, problems: [ { "row" => 2, "reason" => "x", "values" => [ "=1+1" ] } ]) }
    get report_admin_client_import_path(import)
    assert_equal [ "2", "x", "'=1+1" ], CSV.parse(response.body).last
  end

  test "adding duplicates anyway creates them; nothing is merged" do
    import = start_import(duplicates: "create")
    perform_enqueued_jobs(only: ClientImportJob)
    assert_equal [ 4, 0, 1 ], as_business(@business) { import.reload.values_at(:created_count, :skipped_count, :failed_count) }
    assert_equal 2, as_business(@business) { Client.where(display_name: "Maria Lopez").count }
  end

  test "undo removes what it added, keeping clients that already have documents, for a week" do
    import = start_import
    perform_enqueued_jobs(only: ClientImportJob)
    bo = as_business(@business) { Client.find_by!(display_name: "Bo Diaz") }
    as_business(@business) { Quote.create!(client: bo, created_by: @owner) }

    assert_enqueued_with(job: ClientImportUndoJob) { post undo_admin_client_import_path(import) }
    perform_enqueued_jobs(only: ClientImportUndoJob)
    import = as_business(@business) { import.reload }
    assert_equal [ "undone", 1 ], [ import.status, import.undone_count ]
    assert as_business(@business) { Client.exists?(bo.id) }
    assert_not as_business(@business) { Client.exists?(display_name: "Eve") }
    get admin_client_import_path(import)
    assert_select "#import-summary", /1 client removed\. 1 client kept/

    later = start_import("Name\nZed\n")
    perform_enqueued_jobs(only: ClientImportJob)
    travel ClientImport::UNDO_WINDOW + 1.hour do
      post undo_admin_client_import_path(later)
      assert_match "can't be undone", flash[:alert]
    end
  end

  test "an import that breaks partway says so and tells the person who started it" do
    import = start_import
    ClientImport.class_eval { alias_method :original_import_row, :import_row; define_method(:import_row) { |*| raise "boom" } }
    perform_enqueued_jobs(only: ClientImportJob)
    assert_equal "failed", as_business(@business) { import.reload.status }
    assert_match "stopped partway", as_business(@business) { Notification.find_by!(kind: "client_import_finished").title }
  ensure
    ClientImport.class_eval { alias_method :import_row, :original_import_row; remove_method :original_import_row } if ClientImport.private_method_defined?(:original_import_row)
  end

  test "abandoned uploads and old reports are pruned" do
    old = as_business(@business) { ClientImport.create!(filename: "old.csv", headers: [ "Name" ], mapping: { "0" => "display_name" }) }
    old.update_columns(updated_at: 3.days.ago)
    done = as_business(@business) { ClientImport.create!(filename: "done.csv", headers: [ "Name" ], status: "finished", finished_at: 8.days.ago, problems: [ { "row" => 2 } ]) }
    PruneClientImportsJob.perform_now
    assert_not as_business(@business) { ClientImport.exists?(old.id) }
    assert_empty as_business(@business) { done.reload.problems }
  end

  test "another business's import isn't found" do
    theirs = as_business(businesses(:two)) { ClientImport.create!(filename: "x.csv", headers: [ "Name" ], status: "finished", finished_at: Time.current) }
    assert_not_found_across_businesses { get report_admin_client_import_path(theirs) }
    assert_not_found_across_businesses { post undo_admin_client_import_path(theirs) }
  end
end
