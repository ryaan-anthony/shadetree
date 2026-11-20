# NTF-04: every hour, fires "invoice overdue" for invoices whose due date has passed, and runs
# scheduled automations whose time has come but whose job never ran (a deploy, a lost job, or a
# business that was suspended and is active again).
#
# An overdue rule only looks at invoices that fell due after it was made (switching one on
# doesn't chase every old invoice) and that it hasn't run for yet. One business's problem is
# reported and never stops the sweep for the others.
class AutomationsDueJob < ApplicationJob
  queue_as :default

  def perform
    business_ids = Tenancy.across_businesses(reason: "automations sweep") do
      (AutomationRule.active.distinct.pluck(:business_id) + AutomationRun.where(status: "scheduled").distinct.pluck(:business_id)).uniq
    end
    Business.where(id: business_ids).active.find_each { sweep(_1) }
  end

  private

  def sweep(business)
    Tenancy.with_business(business) do
      fire_overdue(business) if business.entitlements.feature?(:automations)
      AutomationRun.due.where(run_at: ...5.minutes.ago).find_each { Automation.perform(_1) }
    end
  rescue StandardError => e
    Rails.error.report(e, context: { business_id: business.id, job: self.class.name })
  end

  def fire_overdue(business)
    AutomationRule.active.where(trigger: "invoice_overdue").find_each do |rule|
      Automation.overdue_without_run(rule, business).find_each { Automation.start(rule, _1) }
    end
  end
end
