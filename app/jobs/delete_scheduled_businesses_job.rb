# OPS-04: deletes businesses whose waiting period is over (or one an operator expedited), and
# tells the owner. Runs daily (config/recurring.yml). Each business on its own: the audit entry
# and email follow its deletion at once, files are removed in the background, and one that
# fails is reported without stopping the rest.
class DeleteScheduledBusinessesJob < ApplicationJob
  queue_as :default

  def perform(business_id = nil)
    scope = Business.where.not(deletion_due_at: nil).where(deletion_due_at: ..Time.current)
    scope = scope.where(id: business_id) if business_id
    scope.pluck(:id).each { delete(_1) }
  end

  private

  def delete(id)
    business = Business.find_by(id:)
    return unless business&.deletion_due_at && business.deletion_due_at <= Time.current

    owner = business.owner
    blob_ids = BusinessDeletion.run!(business)
    AuditEntry.record!(operator: nil, operator_email: "system", action: "business.deleted", business:, user: owner)
    BusinessDeletionMailer.with(email: owner.email, first_name: owner.first_name, business_name: business.name).completed.deliver_later unless owner.deleted?
    PurgeDeletedFilesJob.perform_later(blob_ids) if blob_ids.any?
  rescue StandardError => error
    Rails.error.report(error, context: { business_id: id })
  end
end
