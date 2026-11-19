# NTF-04: every hour, fires "invoice overdue" for invoices whose due date has passed, and runs
# scheduled automations whose time has come but whose job never ran (a deploy, a lost job).
class AutomationsDueJob < ApplicationJob
  queue_as :default

  def perform
    business_ids = Tenancy.across_businesses(reason: "automations sweep") { AutomationRule.active.distinct.pluck(:business_id) }
    Business.where(id: business_ids).active.find_each do |business|
      Tenancy.with_business(business) do
        if AutomationRule.active.exists?(trigger: "invoice_overdue")
          Invoice.where(status: %w[sent partially_paid]).where(due_on: ...business.today).find_each { Automation.trigger("invoice_overdue", _1) }
        end
        AutomationRun.due.where(run_at: ...5.minutes.ago).find_each { Automation.perform(_1) }
      end
    end
  end
end
