# NTF-04: runs a scheduled automation when its delay ends (AutomationsDueJob catches any that
# a restart dropped).
class AutomationRunJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound # the business was deleted

  def perform(run_id, business_id)
    Tenancy.with_business(Business.find(business_id)) do
      run = AutomationRun.find_by(id: run_id)
      Automation.perform(run) if run
    end
  end
end
