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
    Tenancy.with_business(business) { job.attachments.attach(io: png.open, filename: "before.png", content_type: "image/png") }
    variant_blob = ActiveStorage::Blob.create_and_upload!(io: png.open, filename: "v.png")
    ActiveStorage::VariantRecord.create!(blob: business.logo.blob, variation_digest: "x").image.attach(variant_blob)
    blobs = ActiveStorage::Blob.where(id: [ business.logo.blob.id, job.attachments.first.blob.id, variant_blob.id ]).to_a
    AuditEntry.record!(operator: users(:one), action: "business.viewed", business:)
    FeatureFlag.create!(name: "beta", state: "businesses", business_ids: [ business.id, businesses(:two).id ])
    others = Business.where.not(id: business.id).to_h { [ _1.id, rows_of(_1).values.sum ] }
    tables = rows_of(business)
    assert tables.values.sum > 30, "the demo business has data in many tables"

    assert_equal "Oakline Lawn & Landscape", BusinessDeletion.run!(business)

    assert_not Business.exists?(business.id)
    assert_equal({}, rows_of(business).select { _2.positive? }, "rows left behind")
    blobs.each do |blob|
      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert_not blob.service.exist?(blob.key), "file left behind"
    end
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Business", record_id: business.id).count
    assert_equal 0, ActiveStorage::VariantRecord.where(blob_id: blobs.map(&:id)).count
    assert_equal others, Business.where.not(id: business.id).to_h { [ _1.id, rows_of(_1).values.sum ] }
    assert_equal 1, AuditEntry.where(business_id: business.id).count
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
    assert_equal [ "system", due.id ], AuditEntry.find_by!(action: "business.deleted").values_at(:operator_email, :business_id)
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
