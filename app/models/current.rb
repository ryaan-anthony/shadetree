# Per-request (and per-job) context. Reset automatically between requests and jobs.
# Set by BusinessContext for staff requests, ClientLinkContext for client links and
# ApplicationJob for background work. See docs/adr/0014-tenant-scoping-enforcement.md.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :business, :membership

  # Changing the business also moves Time.zone, so times render in the business's zone.
  def business=(business)
    super
    Time.zone = business&.time_zone || Rails.application.config.time_zone
  end

  resets { Time.zone = Rails.application.config.time_zone }
end
