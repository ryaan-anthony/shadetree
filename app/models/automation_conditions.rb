# NTF-04: whether a rule's conditions hold for a record, checked when the run is due.
module AutomationConditions
  module_function

  # nil when they all hold, else why not (shown in the run's log).
  def failing(conditions, subject)
    return "The #{subject.model_name.human.downcase} no longer exists." if subject.nil?

    conditions.each do |key, value|
      reason = case key
      when "still_open" then still_open(subject) unless value.blank? || value == false || value == "0"
      when "total_at_least" then total_at_least(subject, value)
      when "client_tag" then client_tag(subject, value)
      end
      return reason if reason
    end
    nil
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

  def client_tag(subject, tag)
    client = AutomationActions.client_for(subject)
    "The client isn't tagged “#{tag}”." unless client&.tags&.include?(tag.to_s.squish.downcase)
  end
end
