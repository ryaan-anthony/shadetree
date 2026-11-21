require "test_helper"

# OPS-04: deleting a business leaves nothing of it behind (rows in any table, files or their
# variants) and nothing of any other business is touched; the audit log keeps its entries.
class BusinessDeletionTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "every row and file of the business goes; other businesses and the audit log stay" do
    silence_stream { load Rails.root.join("db/seeds/development.rb") }
    business = Business.find_by!(name: "Oakline Lawn & Landscape")
    png = file_fixture("logo.png")
    business.update!(logo: Rack::Test::UploadedFile.new(png, "image/png"))
    job = Tenancy.with_business(business) { Job.first }
    job_blob = ActiveStorage::Blob.create_and_upload!(io: png.open, filename: "before.png", content_type: "image/png")
    Tenancy.with_business(business) { job.attachments.attach(job_blob) }
    variant_blob = ActiveStorage::Blob.create_and_upload!(io: png.open, filename: "v.png")
    ActiveStorage::VariantRecord.create!(blob: business.logo.blob, variation_digest: "x").image.attach(variant_blob)
    # Named, not read back with where(id:): Postgres returns rows in no set order, so "the first
    # two" of a query weren't always the logo and the job's file.
    logo_blob = business.logo.blob
    blobs = [ logo_blob, job_blob, variant_blob ]
    AuditEntry.record!(operator: users(:one), action: "business.viewed", business:)
    audit_before = AuditEntry.where(business_id: business.id).count # incl. the seeded support visit (OPS-03)
    FeatureFlag.create!(name: "beta", state: "businesses", business_ids: [ business.id, businesses(:two).id ])
    others = Business.where.not(id: business.id).to_h { [ _1.id, rows_of(_1).values.sum ] }
    tables = rows_of(business)
    assert tables.values.sum > 30, "the demo business has data in many tables"

    blob_ids = BusinessDeletion.run!(business)
    assert_empty [ logo_blob.id, job_blob.id ] - blob_ids, "the logo and the job's file (the variant goes with the logo)"
    assert ActiveStorage::Blob.exists?(logo_blob.id), "files go afterwards, in the background"
    BusinessDeletion.purge_blobs(blob_ids)

    assert_not Business.exists?(business.id)
    assert_equal({}, rows_of(business).select { _2.positive? }, "rows left behind")
    blobs.each do |blob|
      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert_not blob.service.exist?(blob.key), "file left behind"
    end
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Business", record_id: business.id).count
    assert_equal 0, ActiveStorage::VariantRecord.where(blob_id: blobs.map(&:id)).count
    assert_equal others, Business.where.not(id: business.id).to_h { [ _1.id, rows_of(_1).values.sum ] }
    assert_equal audit_before, AuditEntry.where(business_id: business.id).count, "the audit log keeps its entries"
    assert_equal [ businesses(:two).id ], FeatureFlag.find_by!(name: "beta").business_ids
    assert User.exists?(email: "owner@example.com"), "people keep their accounts"
  end

  test "the daily job deletes businesses past their date and emails the owner" do
    due, later = businesses(:one), businesses(:two)
    due.update_columns(deletion_scheduled_at: 31.days.ago, deletion_due_at: 1.day.ago)
    later.update_columns(deletion_scheduled_at: 1.day.ago, deletion_due_at: 29.days.from_now)
    assert_enqueued_email_with BusinessDeletionMailer, :completed, params: { email: "user1@example.com", first_name: "John", business_name: "Test Business One" } do
      DeleteScheduledBusinessesJob.perform_now
    end
    assert_not Business.exists?(due.id)
    assert Business.exists?(later.id)
    entry = AuditEntry.find_by!(action: "business.deleted")
    assert_equal [ "system", due.id, "Test Business One", due.uid ], [ entry.operator_email, entry.business_id, *entry.data.values_at("business_name", "business_uid") ]
    assert_equal "Test Business One (deleted)", entry.business_label
  end

  test "one business that can't be deleted is reported and the others still go" do
    first, second = businesses(:one), businesses(:two)
    [ first, second ].each { _1.update_columns(deletion_scheduled_at: 31.days.ago, deletion_due_at: 1.day.ago) }
    original = BusinessDeletion.method(:run!)
    BusinessDeletion.define_singleton_method(:run!) { |business| business.id == first.id ? raise("storage down") : original.call(business) }
    DeleteScheduledBusinessesJob.perform_now
    assert Business.exists?(first.id)
    assert_not Business.exists?(second.id)
  ensure
    BusinessDeletion.define_singleton_method(:run!, original) if original
  end

  test "work queued for a business that's since been deleted is dropped, not failed" do
    business = businesses(:one)
    job = Class.new(ApplicationJob) { def perform = raise("should not run") }
    instance = job.new.tap { _1.business_id = business.id }
    business.update_columns(deletion_due_at: 1.day.ago, deletion_scheduled_at: 31.days.ago)
    DeleteScheduledBusinessesJob.perform_now
    assert_nothing_raised { instance.perform_now }
  end

  test "every foreign key into a business's data comes from its own data or says what happens on delete" do
    connection = ActiveRecord::Base.connection
    owned = connection.tables.select { connection.column_exists?(_1, :business_id) } + %w[businesses]
    loose = connection.tables.flat_map do |table|
      connection.foreign_keys(table).select { owned.include?(_1.to_table) && !owned.include?(table) && _1.on_delete.nil? }.map { "#{table}.#{_1.column}" }
    end
    assert_empty loose, "A table outside a business's data points into it without on_delete; BusinessDeletion would fail"
  end

  private

  def rows_of(business)
    connection = ActiveRecord::Base.connection
    tables = connection.tables.select { connection.column_exists?(_1, :business_id) } - BusinessDeletion::KEPT_TABLES
    tables.to_h { [ _1, connection.select_value("SELECT count(*) FROM #{connection.quote_table_name(_1)} WHERE business_id = #{business.id}").to_i ] }
  end

  def silence_stream
    original = $stdout.dup
    $stdout.reopen(File::NULL)
    yield
  ensure
    $stdout.reopen(original)
  end
end
