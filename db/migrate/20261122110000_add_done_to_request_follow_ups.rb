# JOB-06: the assignee marks their follow-up done (it stays theirs until they create the quote or
# pass the request back), and the request's history records it.
class AddDoneToRequestFollowUps < ActiveRecord::Migration[8.1]
  def change
    change_table :request_follow_ups, bulk: true do |t|
      t.datetime :done_at
      t.references :done_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
    end
    remove_check_constraint :service_request_events, name: "service_request_events_kind",
                            expression: "kind IN ('assigned', 'reassigned', 'rescheduled', 'updated', 'unassigned', 'ended')"
    add_check_constraint :service_request_events, "kind IN ('assigned', 'reassigned', 'rescheduled', 'updated', 'unassigned', 'ended', 'done', 'passed_back')",
                         name: "service_request_events_kind"
  end
end
