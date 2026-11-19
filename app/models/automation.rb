# NTF-04: the automation engine.
#
#   Automation.trigger("quote_sent", quote)     # from the core flow (ClientEvent, Job, a daily scan)
#
# Each active rule for the trigger gets one AutomationRun for the record (never two), run now
# or when its delay ends (AutomationRunJob, and AutomationsDueJob as a sweep). Running re-checks
# the conditions and does the actions, each logged. Safeguards: nothing triggers while an
# automation is acting (no loops), nothing runs for a suspended business, and a client never
# gets the same template twice about one document (AutomationDelivery).
module Automation
  module_function

  # ClientEvent kinds that are triggers, and their trigger names.
  EVENTS = { "request_received" => "request_received", "quote_sent" => "quote_sent", "quote_viewed" => "quote_viewed",
             "quote_approved" => "quote_approved", "quote_declined" => "quote_declined", "visit_scheduled" => "visit_scheduled",
             "invoice_sent" => "invoice_sent", "payment_recorded" => "payment_received" }.freeze

  def trigger(trigger, subject)
    return if Current.automation_run || subject.nil?

    business = subject.business
    return unless business.active? && business.entitlements.feature?(:automations)

    Tenancy.with_business(business) do
      AutomationRule.active.where(trigger:).find_each do |rule|
        run = AutomationRun.create_with(rule_name: rule.name, trigger:, run_at: Time.current + rule.delay)
                           .create_or_find_by!(rule:, subject:)
        next unless run.previously_new_record?

        rule.delay.zero? ? perform(run) : AutomationRunJob.set(wait_until: run.run_at).perform_later(run.id, business.id)
      end
    end
  end

  # Runs a scheduled run: conditions re-checked, actions done, all logged. Safe to call twice.
  def perform(run)
    run.with_lock do
      return unless run.status == "scheduled"

      rule = run.rule
      skip = skip_reason(run, rule)
      if skip
        run.note!("run", "skipped", skip)
        return run.update!(status: "skipped", finished_at: Time.current)
      end

      Current.set(automation_run: run) do
        rule.actions.each { |action| AutomationActions.perform(action, run) }
      end
      failed = run.log.any? { _1["result"] == "failed" }
      run.update!(status: failed ? "failed" : "done", finished_at: Time.current)
    end
  end

  def skip_reason(run, rule)
    return "The automation was deleted." unless rule
    return "The automation is switched off." unless rule.enabled?
    return "The business is suspended." unless run.business.active?
    return "Automations aren't included in the plan any more." unless run.business.entitlements.feature?(:automations)

    AutomationConditions.failing(rule.conditions, run.subject)
  end
end
