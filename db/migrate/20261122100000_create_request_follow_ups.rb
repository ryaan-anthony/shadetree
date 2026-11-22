# CLI-07: a request's follow-up: the team member it's assigned to, as a site visit or a call, on
# a day (a start time, an arrival window or anytime that day, as visits are) with a duration and
# instructions for them. A request has at most one; it's changed in place while the request is
# open and removed when it's unassigned, quoted or archived. service_request_events records who
# assigned, moved or took it off whom, for the request's history.
class CreateRequestFollowUps < ActiveRecord::Migration[8.1]
  def change
    create_table :request_follow_ups do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false
      t.references :service_request, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :assigned_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :kind, null: false, default: "visit"
      t.date :scheduled_on, null: false
      t.string :timing, null: false, default: "anytime"
      t.datetime :starts_at
      t.datetime :window_ends_at
      t.integer :duration_minutes, null: false, default: 60
      t.text :instructions
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint "kind IN ('visit', 'call')", name: "request_follow_ups_kind"
      t.check_constraint "timing IN ('exact', 'window', 'anytime')", name: "request_follow_ups_timing"
      t.check_constraint "(timing = 'anytime') = (starts_at IS NULL) AND (timing = 'window') = (window_ends_at IS NOT NULL)", name: "request_follow_ups_times"
      t.check_constraint "duration_minutes BETWEEN 5 AND 1440", name: "request_follow_ups_duration"
    end
    add_index :request_follow_ups, :uid, unique: true
    add_index :request_follow_ups, %i[business_id user_id scheduled_on]

    create_table :service_request_events do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :service_request, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.check_constraint "kind IN ('assigned', 'reassigned', 'rescheduled', 'updated', 'unassigned', 'ended')", name: "service_request_events_kind"
    end
  end
end
