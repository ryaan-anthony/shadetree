# JOB-05: telling a client about their visits. #update is one email for a job's settled
# changes (booked, moved, cancelled: see VisitClientNotice); #reminder is the day before.
# Each visit links to its client page (PLT-12).
class VisitMailer < ClientMailer
  Item = Data.define(:visit, :kind, :before, :link)

  def update
    @job = Job.includes(:client, :property).find(params[:job_id])
    visits = @job.visits.where(id: params[:changes].map { _1["visit_id"] }).index_by(&:id)
    @items = params[:changes].filter_map do |change|
      visit = visits[change["visit_id"]] or next
      Item.new(visit, change["kind"], change["before"], visit.client_link!)
    end
    client_mail subject: self.class.update_subject(@items)
  end

  def reminder
    @job = Job.includes(:client, :property).find(params[:job_id])
    visit = @job.visits.find(params[:visit_id])
    @items = [ Item.new(visit, "reminder", nil, visit.client_link!) ]
    client_mail subject: "Reminder: your visit tomorrow, #{visit.when_label}"
  end

  def self.update_subject(items)
    kinds = items.map(&:kind).uniq
    first = items.first.visit
    return "Changes to your visits" unless kinds.one?

    case kinds.first
    when "scheduled" then items.one? ? "Visit booked: #{first.when_label}" : "#{items.size} visits booked, from #{first.scheduled_on.strftime("%b %-d")}"
    when "changed" then items.one? ? "Visit moved to #{first.when_label}" : "#{items.size} visits moved"
    else items.one? ? "Visit cancelled: #{first.scheduled_on.strftime("%a, %b %-d")}" : "#{items.size} visits cancelled"
    end
  end
end
