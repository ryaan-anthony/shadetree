# Per-request (and per-job) context. Reset automatically between requests and jobs.
# Set by BusinessContext for staff requests, ClientLinkAccess for client links and
# ApplicationJob for background work. See docs/adr/0014-tenant-scoping-enforcement.md.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :business, :membership
  attribute :automation_run # NTF-04: set while an automation acts, so its effects trigger no others

  # Changing the business also moves Time.zone, so times render in the business's zone.
  def business=(business)
    super
    Time.zone = business&.time_zone || Rails.application.config.time_zone
  end

  resets { Time.zone = Rails.application.config.time_zone }
end
