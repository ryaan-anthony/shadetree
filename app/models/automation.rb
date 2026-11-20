# NTF-04: the automation engine.
#
#   Automation.trigger("quote_sent", quote)     # from the core flow (ClientEvent, Job, a daily scan)
#
# Each active rule for the trigger gets one AutomationRun for the record (never two), run now
# or when its delay ends (AutomationRunJob, and AutomationsDueJob as a sweep). Running re-checks
# the conditions and does the actions, each logged. Safeguards: nothing triggers while an
# automation is acting (no loops: the flag is taken when the event is recorded, see ClientEvent
# and Job#complete!), runs wait while a business is suspended (those that came due meanwhile are
# skipped when it's reactivated), and a client never gets the same template twice about one
# document (AutomationDelivery). Runs always go through a job, so a
# failing automation never breaks the request that triggered it.
module Automation
  module_function

  # ClientEvent kinds that are triggers, and their trigger names.
  EVENTS = { "request_received" => "request_received", "quote_sent" => "quote_sent", "quote_viewed" => "quote_viewed",
             "quote_approved" => "quote_approved", "quote_declined" => "quote_declined", "visit_scheduled" => "visit_scheduled",
             "invoice_sent" => "invoice_sent", "payment_recorded" => "payment_received" }.freeze

  # Never raises: an automation going wrong is reported, not passed to whoever triggered it.
  def trigger(trigger, subject)
    return if Current.automation_run || subject.nil?

    business = subject.business
    return unless business.active? && business.entitlements.feature?(:automations)

    Tenancy.with_business(business) do
      AutomationRule.active.where(business_id: business.id, trigger:).find_each { start(_1, subject) }
    end
  rescue StandardError => e
    Rails.error.report(e, context: { automation_trigger: trigger, subject: subject&.to_global_id&.to_s })
  end

  MISSED_WHILE_SUSPENDED = "It came due while the business was suspended.".freeze

  # OPS-04 (owner's decision): on reactivation, runs that came due during the suspension are
  # skipped rather than all firing at once, and invoices that fell overdue meanwhile get a skipped
  # run so the hourly sweep doesn't chase them. Later events run as usual.
  def skip_missed_during_suspension(business)
    Tenancy.with_business(business) do
      AutomationRun.where(status: "scheduled", run_at: ..Time.current).find_each do |run|
        run.with_lock do
          next unless run.status == "scheduled"

          run.note!("run", "skipped", MISSED_WHILE_SUSPENDED)
          run.update!(status: "skipped", finished_at: Time.current)
        end
      end
      AutomationRule.active.where(trigger: "invoice_overdue").find_each do |rule|
        overdue_without_run(rule, business).find_each do |invoice|
          AutomationRun.create_or_find_by!(rule:, subject: invoice) do |run|
            run.assign_attributes(rule_name: rule.name, trigger: rule.trigger, run_at: Time.current, status: "skipped", finished_at: Time.current,
                                  log: [ { "action" => "run", "result" => "skipped", "detail" => MISSED_WHILE_SUSPENDED } ])
          end
        end
      end
    end
  end

  # Invoices an overdue rule would fire for now: fell due after the rule was made, no run yet.
  def overdue_without_run(rule, business)
    Invoice.where(status: %w[sent partially_paid], due_on: rule.created_at.in_time_zone(business.time_zone).to_date...business.today)
           .where.not(id: AutomationRun.where(rule:, subject_type: "Invoice").select(:subject_id))
  end

  # One run of a rule for a record (never two), handed to a job for when its delay ends.
  def start(rule, subject)
    run = AutomationRun.create_with(rule_name: rule.name, trigger: rule.trigger, run_at: Time.current + rule.delay)
                       .create_or_find_by!(rule:, subject:)
    AutomationRunJob.set(wait_until: run.run_at).perform_later(run.id, rule.business_id) if run.previously_new_record?
    run
  end

  # Runs a scheduled run: conditions re-checked, actions done, all logged. Safe to call twice.
  # A run waits (stays scheduled) while its business is suspended. If something unexpected goes
  # wrong the run is marked failed with the error, so it isn't retried forever.
  def perform(run)
    Current.set(automation_run: run) do
      run.with_lock do
        next unless run.status == "scheduled" && run.business.active?

        rule = run.rule
        skip = skip_reason(run, rule)
        if skip
          run.note!("run", "skipped", skip)
          next run.update!(status: "skipped", finished_at: Time.current)
        end

        rule.actions.each { |action| AutomationActions.perform(action, run) }
        failed = run.log.any? { _1["result"] == "failed" }
        run.update!(status: failed ? "failed" : "done", finished_at: Time.current)
      end
    end
  rescue StandardError => e
    Rails.error.report(e, context: { automation_run_id: run.id })
    run.reload
    return unless run.status == "scheduled"

    log = (run.log.is_a?(Array) ? run.log : []) + [ { "action" => "run", "result" => "failed", "detail" => "Something went wrong running this automation." } ]
    run.update_columns(status: "failed", finished_at: Time.current, log:)
  end

  def skip_reason(run, rule)
    return "The automation was deleted." unless rule
    return "The automation is switched off." unless rule.enabled?
    return "Automations aren't included in the plan any more." unless run.business.entitlements.feature?(:automations)
    return "The automation now starts on something else." if run.trigger != rule.trigger
    return "The record no longer exists." unless run.subject
    return "The client's details were erased." if AutomationActions.client_erased?(run.subject)

    AutomationConditions.failing(rule.conditions, run.subject)
  end
end
