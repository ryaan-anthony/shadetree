module ServiceRequestsHelper
  # CLI-07: one line of a request's follow-up history. `people` maps user ids to members, for
  # the names (a deleted account reads "a former member").
  def request_event_text(event, people)
    data = event.data
    name = ->(id) { (person = people[id]) && !person.deleted? ? person.full_name : "a former member" }
    what = ->(state) { "#{RequestFollowUp::KIND_LABELS.fetch(state["kind"], "Follow-up").downcase}, #{state["when"]}" }
    case event.kind
    when "assigned" then "Assigned to #{name.(data.dig("to", "user_id"))}: #{what.(data["to"])}"
    when "reassigned" then "Handed from #{name.(data["from_user_id"])} to #{name.(data["to_user_id"])}"
    when "rescheduled" then "Moved from #{data.dig("from", "when")} to #{data.dig("to", "when")}"
    when "updated"
      changed = data["changed"].map { { "kind" => "made it a #{RequestFollowUp::KIND_LABELS.fetch(data.dig("to", "kind"), "follow-up").downcase}", "duration_minutes" => "changed the duration",
                                        "instructions" => "changed the instructions" }.fetch(_1, _1) }
      changed.to_sentence.upcase_first
    when "unassigned" then "Taken off #{name.(data.dig("from", "user_id"))}"
    when "ended" then "Taken off #{name.(data.dig("from", "user_id"))}: the request was #{data["reason"]}"
    else event.kind.humanize
    end
  end
end
