# OPS-04: deletes businesses whose waiting period is over (or one an operator expedited), and
# tells the owner. Runs daily (config/recurring.yml).
class DeleteScheduledBusinessesJob < ApplicationJob
  queue_as :default

  def perform(business_id = nil)
    scope = Business.where.not(deletion_due_at: nil).where(deletion_due_at: ..Time.current)
    scope = scope.where(id: business_id) if business_id
    scope.find_each do |business|
      owner = business.owner
      name = BusinessDeletion.run!(business)
      AuditEntry.record!(operator: nil, operator_email: "system", action: "business.deleted", business:, user: owner, name:)
      BusinessDeletionMailer.with(email: owner.email, first_name: owner.first_name, business_name: name).completed.deliver_later unless owner.deleted?
    end
  end
end
