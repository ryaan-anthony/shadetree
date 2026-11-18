# JOB-05: sends a job's settled visit changes to the client (VisitClientNotice). Ids, not
# records: a business-owned record can't be loaded before its business is set.
class VisitClientNoticeJob < ApplicationJob
  queue_as :default

  def perform(business_id, job_id)
    business = Business.find_by(id: business_id) or return
    Tenancy.with_business(business) { (job = Job.find_by(id: job_id)) && VisitClientNotice.deliver_due(job) }
  end
end
