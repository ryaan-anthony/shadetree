# JOB-05: the email a client gets about a job's visits once its changes have settled: which
# were booked, moved or cancelled since they were last told. Run by VisitClientNoticeJob a few
# minutes after the last change (Job::CLIENT_NOTICE_DELAY), so a burst of edits is one email,
# and a change that ends where it started is none.
class VisitClientNotice
  # kind: "scheduled", "changed" or "cancelled"; before: the old "when". The email shows the
  # visit as it was here ("when"), even if it changes again before the email is delivered.
  Change = Data.define(:visit, :kind, :before)

  KINDS = { "scheduled" => "visit_scheduled", "changed" => "visit_changed", "cancelled" => "visit_cancelled" }.freeze
  HOURLY_LIMIT_WAIT = 15.minutes

  def self.deliver_due(job) = new(job).deliver_due

  def initialize(job)
    @job = job
    @business = job.business
  end

  # Sends what's due (nothing if a later change pushed it back) and records what the client now
  # knows, in one transaction with queueing the email, so neither happens without the other.
  # Returns the EmailMessage, or nil.
  def deliver_due
    @job.with_lock do
      due = @job.client_notice_due_at
      next if due.nil? || due > 1.second.from_now

      # The business's client email limit (NTF-01): try again shortly rather than drop it.
      next postpone if EmailMessage.hourly_limit_reached?

      # Visits from the day the changes were made, so one late in the evening still counts.
      from = (due - Job::CLIENT_NOTICE_DELAY).in_time_zone(@job.location.time_zone).to_date
      visits = @job.visits.where(scheduled_on: from..).where(status: %w[scheduled cancelled]).includes(:business).in_order.to_a
      changes = sendable(visits.filter_map { change_for(_1) })
      emailing = changes.map(&:visit)
      visits.each do |visit|
        next if visit.client_up_to_date? && !emailing.include?(visit)

        # emailed_at: so tomorrow's reminder isn't sent hours after this email (VisitReminders).
        state = visit.client_state
        state["emailed_at"] = Time.current.iso8601 if emailing.include?(visit)
        visit.update_columns(client_told: state)
      end
      @job.update_columns(client_notice_due_at: nil)
      send_email(changes)
    end
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

  def recipient = @job.client.primary_email&.value

  # The changes an email would carry: none without an address; only the kinds the business sends.
  def sendable(changes) = recipient ? changes.select { @business.client_visit_email?(_1.kind) } : []

  def postpone
    due = HOURLY_LIMIT_WAIT.from_now
    @job.update_columns(client_notice_due_at: due)
    ids = [ @business.id, @job.id ]
    ActiveRecord.after_all_transactions_commit { VisitClientNoticeJob.set(wait_until: due).perform_later(*ids) }
    nil
  end

  def send_email(changes)
    return if changes.empty?

    kinds = changes.map(&:kind).uniq
    kind = KINDS.fetch(kinds.one? ? kinds.first : "changed")
    VisitMailer.send_later(:update, business: @business, to: recipient, kind:, related: @job, job_id: @job.id,
                                    changes: changes.map { { "visit_id" => _1.visit.id, "kind" => _1.kind, "before" => _1.before, "when" => _1.visit.when_label } })
  end
end
