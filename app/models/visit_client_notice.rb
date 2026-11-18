# JOB-05: the email a client gets about a job's visits once its changes have settled: which
# were booked, moved or cancelled since they were last told. Run by VisitClientNoticeJob a few
# minutes after the last change (Job::CLIENT_NOTICE_DELAY), so a burst of edits is one email,
# and a change that ends where it started is none.
class VisitClientNotice
  Change = Data.define(:visit, :kind, :before) # kind: "scheduled", "changed" or "cancelled"; before: the old "when"

  KINDS = { "scheduled" => "visit_scheduled", "changed" => "visit_changed", "cancelled" => "visit_cancelled" }.freeze

  def self.deliver_due(job) = new(job).deliver_due

  def initialize(job)
    @job = job
    @business = job.business
  end

  # Sends what's due (nothing if a later change pushed it back) and records what the client now
  # knows. Returns the EmailMessage, or nil.
  def deliver_due
    changes = nil
    @job.with_lock do
      next if @job.client_notice_due_at.nil? || @job.client_notice_due_at > 1.second.from_now

      visits = @job.visits.where(scheduled_on: @business.today..).where(status: %w[scheduled cancelled]).includes(:business).in_order.to_a
      changes = visits.filter_map { change_for(_1) }
      visits.each { _1.update_columns(client_told: _1.client_state) unless _1.client_up_to_date? }
      @job.update_columns(client_notice_due_at: nil)
    end
    send_email(changes) if changes.present?
  end

  private

  def change_for(visit)
    told, now = visit.client_told, visit.client_state
    if now["state"] == "cancelled"
      Change.new(visit, "cancelled", nil) if told&.dig("state") == "booked"
    elsif told.nil? || told["state"] == "cancelled"
      Change.new(visit, "scheduled", nil)
    elsif !visit.client_up_to_date?
      Change.new(visit, "changed", told["when"])
    end
  end

  def send_email(changes)
    changes = changes.select { @business.client_visit_email?(_1.kind) }
    to = @job.client.primary_email&.value
    return if changes.empty? || to.nil?

    kinds = changes.map(&:kind).uniq
    kind = KINDS.fetch(kinds.one? ? kinds.first : "changed")
    VisitMailer.send_later(:update, business: @business, to:, kind:, related: @job, job_id: @job.id,
                                    changes: changes.map { { "visit_id" => _1.visit.id, "kind" => _1.kind, "before" => _1.before } })
  end
end
