# NTF-04: automations described in plain words, and the form's delay split into an amount and unit.
module AutomationsHelper
  def automation_delay_label(minutes)
    return "Right away" if minutes.zero?

    amount, unit = automation_delay_parts(minutes)
    "#{pluralize(amount, unit.singularize)} later"
  end

  # [amount, "days" | "hours" | "minutes"]
  def automation_delay_parts(minutes)
    return [ 0, "hours" ] if minutes.zero?
    return [ minutes / 1440, "days" ] if minutes.positive? && (minutes % 1440).zero?
    return [ minutes / 60, "hours" ] if minutes.positive? && (minutes % 60).zero?

    [ minutes, "minutes" ]
  end

  # "3 days after a quote is sent, if it's still open: email “Quote follow-up”."
  def automation_summary(rule, templates)
    event = rule.trigger_definition.label.sub(/\A\w/, &:downcase)
    timing = rule.delay_minutes.zero? ? "When #{event}" : "#{automation_delay_label(rule.delay_minutes).delete_suffix(" later")} after #{event}"
    conditions = rule.conditions.filter_map { |key, value| automation_condition_phrase(key, value) }
    actions = rule.actions.map { automation_action_phrase(_1, templates) }
    [ timing, (", if #{conditions.to_sentence}" if conditions.any?), ": ", actions.to_sentence, "." ].join
  end

  def automation_condition_phrase(key, value)
    case key
    when "still_open" then "it's still open" unless AutomationConditions.off?(value)
    when "paid_in_full" then "it's paid in full" unless AutomationConditions.off?(value)
    when "total_at_least" then "the total is at least #{Money.parse(value.to_s, current_business.currency).format}"
    when "client_tag" then "the client is tagged “#{value}”"
    when "location" then "it's for #{Location.find_by(uid: value.to_s)&.name || "a removed location"}"
    end
  end

  def automation_action_phrase(action, templates)
    case action["type"]
    when "send_template" then "email “#{templates[action["template"]]&.name || "a deleted template"}”"
    when "notify_team" then "notify #{AutomationRule::TEAMS.fetch(action["team"], "the team").sub("Everyone", "everyone")}"
    when "create_job" then "create a job"
    when "invoice_job" then "create and send the invoice"
    when "tag_client" then "tag the client “#{action["tag"]}”"
    else "an unknown step"
    end
  end

  def automation_run_tone(status)
    { "done" => :success, "skipped" => :neutral, "failed" => :danger, "scheduled" => :info }.fetch(status, :neutral)
  end

  def automation_run_status(run)
    case run.status
    when "scheduled" then "Waiting"
    when "done" then "Done"
    when "skipped" then "Skipped"
    when "failed" then "Didn't finish"
    end
  end

  # The record a run was about, linked where staff can see it.
  def automation_run_subject(run)
    subject = run.subject
    return tag.span("A deleted record", class: "text-muted") unless subject

    label = subject.is_a?(Payment) ? "a payment on #{subject.invoice.number}" : AutomationActions.label_for(subject)
    path = AutomationActions.notice_path(subject)
    path ? link_to(label, path, class: "font-medium text-canopy hover:underline") : label
  end
end
