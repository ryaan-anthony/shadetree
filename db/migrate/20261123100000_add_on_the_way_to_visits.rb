# JOB-12: "On my way": the arrival time the client was given (on their visit page), who sent it
# last, and the arrival time in the last email they got (an update emails only when the time
# moves 10+ minutes from it). Each send is in the visit's history.
class AddOnTheWayToVisits < ActiveRecord::Migration[8.1]
  KINDS = %w[scheduled rescheduled reassigned updated cancelled restored started completed reopened].freeze

  def change
    add_column :visits, :on_the_way_arrives_at, :datetime
    add_column :visits, :on_the_way_emailed_arrives_at, :datetime
    add_column :visits, :on_the_way_by_id, :bigint
    add_foreign_key :visits, :users, column: :on_the_way_by_id, on_delete: :nullify
    add_index :visits, :on_the_way_by_id, where: "on_the_way_by_id IS NOT NULL" # the foreign key's nullify on a user's delete

    remove_check_constraint :visit_events, "kind IN (#{KINDS.map { "'#{_1}'" }.join(", ")})", name: "visit_events_kind"
    add_check_constraint :visit_events, "kind IN (#{(KINDS + [ "on_the_way" ]).map { "'#{_1}'" }.join(", ")})", name: "visit_events_kind"
  end
end
