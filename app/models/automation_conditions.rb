# NTF-04: whether a rule's conditions hold for a record, checked when the run is due.
module AutomationConditions
  module_function

  # nil when they all hold, else why not (shown in the run's log).
  def failing(conditions, subject)
    return "The record no longer exists." if subject.nil?

    conditions.each do |key, value|
      reason = case key
      when "still_open" then still_open(subject) unless off?(value)
      when "paid_in_full" then paid_in_full(subject) unless off?(value)
      when "total_at_least" then total_at_least(subject, value)
      when "client_tag" then client_tag(subject, value)
      when "location" then location(subject, value)
      end
      return reason if reason
    end
    nil
  end

  def off?(value) = value.blank? || value == false || value == "0"

  def paid_in_full(subject)
    invoice = subject.is_a?(Payment) ? subject.invoice : subject
    "The invoice isn't paid in full." unless invoice.is_a?(Invoice) && invoice.status == "paid"
  end

  def still_open(subject)
    case subject
    when Quote then "The quote is #{subject.state_label.downcase} now." unless subject.status == "sent"
    when Invoice, Payment
      invoice = subject.is_a?(Payment) ? subject.invoice : subject
      "The invoice is #{invoice.status_label.downcase} now." unless invoice.outstanding?
    when Job then "The job is #{subject.status_label.downcase} now." unless subject.open?
    end
  end

  def total_at_least(subject, amount)
    document = AutomationActions.document_for(subject)
    return "There's no total to compare." unless document.respond_to?(:totals)

    minimum = Money.parse(amount.to_s, document.currency)
    "The total is under #{minimum.format}." if document.totals.total < minimum
  end

  # CAT-07: the record's location (a visit's job's, a payment's invoice's).
  def location(subject, uid)
    document = case subject
    when Visit then subject.job
    when Payment then subject.invoice
    else subject
    end
    here = document.try(:location)
    return if here&.uid == uid.to_s

    "Only for #{Location.find_by(uid: uid.to_s)&.name || "another location"}; this is for #{here&.name || "no location"}."
  end

  def client_tag(subject, tag)
    client = AutomationActions.client_for(subject)
    "The client isn't tagged “#{tag}”." unless client&.tags&.include?(tag.to_s.squish.downcase)
  end
end
