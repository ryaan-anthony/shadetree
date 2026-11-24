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

  # JOB-12: someone's on the way. Fixed wording (the business can change the subject and opening
  # in NTF-03): the arrival time, the window, the address, who's coming (photo inside the email,
  # first name, title, ACC-09) and a phone for each, or the business's once.
  def on_the_way
    @job = Job.includes(:client, :property).find(params[:job_id])
    @visit = @job.visits.find(params[:visit_id])
    @arrives_at = Time.iso8601(params[:arrives_at])
    kind = @email_message&.kind || params[:kind] || "visit_on_the_way" # the first, or its update
    values = MessageTemplate::Values.visit(@job, @visit.when_label).merge(MessageTemplate::Values.on_the_way(@visit, arrives_at: @arrives_at))
    @headline = "#{values["on_the_way"]}, arriving #{values["arrival_time"]}"
    subject = custom_subject(kind, values) || MessageTemplate.render_subject(MessageTemplate.definition(kind).subject, values)
    @intro ||= MessageTemplate.render(MessageTemplate.definition(kind).body, values)
    # Started, ended or moved before it went: the card's gone, so the email would be wrong.
    return skip_changed_document(subject:, error: "The visit started, ended or moved before the email went.") unless @visit.on_the_way?

    @team = @visit.on_the_way_team
    @photos = @team.to_h { [ _1.id, attach_team_photo(_1) ] }
    @link = @visit.client_link!
    client_mail subject:
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

  private

  # Inside the email, like the logo (ClientMailer#attach_logo): no permanent public URL, nothing
  # fetched from us when it's opened. nil (the initial shows) if it can't be read.
  def attach_team_photo(member)
    return unless member.photo.attached?

    image = member.photo.variant(:card).processed.image
    name = "team-#{member.uid}.#{image.filename.extension.presence || "jpg"}"
    attachments.inline[name] = { mime_type: image.content_type, content: image.download }
    attachments.inline[name].url
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { business_id: @business.id, team_photo: member.id })
    nil
  end
end
