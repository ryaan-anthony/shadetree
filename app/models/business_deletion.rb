# OPS-04: permanently removes a business: every row of its data, and every file attached to it
# (logo, photos, attachments, PDFs and their variants). A connected Stripe account is
# disconnected first (PAY-03), never deleted. The operator audit log keeps its
# entries, as written (they have no foreign keys and can't be deleted).
#
#   blob_ids = BusinessDeletion.run!(business)  # the rows are gone once this returns
#   PurgeDeletedFilesJob.perform_later(blob_ids)  # then the files, in the background
class BusinessDeletion
  KEPT_TABLES = %w[audit_entries].freeze

  def self.run!(business) = new(business).run!

  def initialize(business)
    @business = business
  end

  def run!
    release_payment_accounts
    attachments = business_attachments
    blob_ids = (attachments.map(&:blob_id) + pdf_blob_ids).uniq
    Tenancy.across_businesses(reason: "deleting a business and all its data (OPS-04)") do
      ApplicationRecord.transaction do
        ActiveStorage::Attachment.where(id: attachments.map(&:id)).delete_all
        tables_in_deletion_order.each do |table|
          rows = Arel::Table.new(table)
          connection.delete(Arel::DeleteManager.new.from(rows).where(rows[:business_id].eq(@business.id)))
        end
        FeatureFlag.where("? = ANY(business_ids)", @business.id).find_each { _1.update!(business_ids: _1.business_ids - [ @business.id ]) }
        Business.where(id: @business.id).delete_all
      end
    end
    blob_ids
  end

  # Each file and its variants, unless something else still uses it. A file that can't be
  # removed is reported and the rest go on.
  def self.purge_blobs(ids)
    ActiveStorage::Blob.where(id: ids).find_each do |blob|
      next if blob.attachments.exists?

      ActiveStorage::VariantRecord.where(blob_id: blob.id).find_each do |variant|
        variant.image.purge if variant.image.attached?
        variant.delete
      end
      blob.purge
    rescue StandardError => error
      Rails.error.report(error, context: { blob_id: blob.id })
    end
  end

  private

  def connection = ApplicationRecord.connection

  # PAY-03: Shadetree's access to the business's Stripe account ends before its records go; the
  # business keeps its Stripe account, money and history. If Stripe can't be reached this
  # raises and nothing is deleted (the daily job tries again).
  def release_payment_accounts
    Tenancy.with_business(@business) { PaymentAccount.connected.find_each { _1.disconnect!(reason: "business_deleted") } }
  end

  def business_tables
    @business_tables ||= connection.tables.select { connection.column_exists?(_1, :business_id) } - KEPT_TABLES
  end

  # Children before the tables they point at, so no foreign key is left dangling.
  def tables_in_deletion_order
    parents = business_tables.index_with do |table|
      connection.foreign_keys(table).map(&:to_table).select { business_tables.include?(_1) && _1 != table }
    end
    ordered = []
    visit = ->(table, path = []) do
      return if ordered.include?(table) || path.include?(table)

      business_tables.select { parents[_1].include?(table) }.each { visit.call(_1, path + [ table ]) }
      ordered << table
    end
    business_tables.each { visit.call(_1) }
    ordered
  end

  # Attachments on the business itself and on every record it owns.
  def business_attachments
    ActiveStorage::Attachment.distinct.pluck(:record_type).flat_map do |type|
      model = type.safe_constantize
      ids = if model == Business then [ @business.id ]
      elsif model && model < ActiveRecord::Base && model.column_names.include?("business_id")
        Tenancy.across_businesses(reason: "deleting a business's files (OPS-04)") { model.unscoped.where(business_id: @business.id).pluck(:id) }
      end
      ids.present? ? ActiveStorage::Attachment.where(record_type: type, record_id: ids).to_a : []
    end
  end

  # Files a record points at directly (stored PDFs) rather than through an attachment.
  def pdf_blob_ids
    business_tables.flat_map do |table|
      rows = Arel::Table.new(table)
      connection.columns(table).map(&:name).grep(/_blob_id\z/).flat_map do |column|
        connection.select_values(rows.project(rows[column]).where(rows[:business_id].eq(@business.id).and(rows[column].not_eq(nil))))
      end
    end
  end
end
