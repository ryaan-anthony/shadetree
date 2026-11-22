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
    when "done" then "#{RequestFollowUp::KIND_LABELS.fetch(data.dig("from", "kind"), "Follow-up")} done"
    when "passed_back" then "Passed back from #{name.(data["from_user_id"])} to #{name.(data["to_user_id"])}"
    when "unassigned" then "Taken off #{name.(data.dig("from", "user_id"))}"
    when "ended"
      why = { "quoted" => "the request was quoted", "archived" => "the request was archived", "left_team" => "they left the team",
              "role_changed" => "their role changed" }.fetch(data["reason"], data["reason"])
      "Taken off #{name.(data.dig("from", "user_id"))}: #{why}"
    else event.kind.humanize
    end
  end
end
