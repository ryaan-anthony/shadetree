# JOB-05: telling a client about their visits. #update is one email for a job's settled
# changes (booked, moved, cancelled: see VisitClientNotice); #reminder is the day before.
# Each visit links to its client page (PLT-12).
class VisitMailer < ClientMailer
  # when: the visit's day and time as it was when the email was decided (VisitClientNotice).
  Item = Data.define(:visit, :kind, :before, :when, :link)

  def update
    @job = Job.includes(:client, :property).find(params[:job_id])
    visits = @job.visits.includes(:business).where(id: params[:changes].map { _1["visit_id"] }).index_by(&:id)
    @items = params[:changes].filter_map do |change|
      visit = visits[change["visit_id"]] or next
      Item.new(visit, change["kind"], change["before"], change["when"] || visit.when_label, visit.client_link!)
    end
    # A business's wording is about one visit; several in one email keep the standard wording,
    # which counts them and says what happened to each.
    subject = custom_subject("visit_#{@items.first.kind}", MessageTemplate::Values.visit(@job, @items.first.when)) if @items.one?
    client_mail subject: subject || self.class.update_subject(@items)
  end

  def reminder
    @job = Job.includes(:client, :property).find(params[:job_id])
    visit = @job.visits.find(params[:visit_id])
    @items = [ Item.new(visit, "reminder", nil, visit.when_label, visit.client_link!) ]
    subject = custom_subject("visit_reminder", MessageTemplate::Values.visit(@job, visit.when_label))
    client_mail subject: subject || "Reminder: your visit tomorrow, #{visit.when_label}"
  end

  def self.update_subject(items)
    kinds = items.map(&:kind).uniq
    first = items.first
    return "Changes to your visits" unless kinds.one?

    from = first.visit.scheduled_on
    from = from.strftime(from.year == first.visit.business.today.year ? "%b %-d" : "%b %-d, %Y")
    case kinds.first
    when "scheduled" then items.one? ? "Visit booked: #{first.when}" : "#{items.size} visits booked, from #{from}"
    when "changed" then items.one? ? "Visit moved to #{first.when}" : "#{items.size} visits moved"
    else items.one? ? "Visit cancelled: #{first.when}" : "#{items.size} visits cancelled"
    end
  end
end
