# JOB-02: a job happens through visits. Each visit is on one date (multi-day work is a visit per
# day), with a start time, an arrival window, or "anytime" that day; an estimated duration; the
# members going (any role, or nobody yet); and its own instructions. Times are stored in UTC
# and entered and shown in the business's time zone. visit_events records who changed what.
class CreateVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false
      t.references :job, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :scheduled_on, null: false
      t.string :timing, null: false, default: "anytime"
      t.datetime :starts_at   # a start time, or the window's start
      t.datetime :window_ends_at
      t.integer :duration_minutes, null: false, default: 60
      t.text :instructions
      t.string :status, null: false, default: "scheduled"
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.string :cancel_reason
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint "timing IN ('exact', 'window', 'anytime')", name: "visits_timing"
      t.check_constraint "status IN ('scheduled', 'in_progress', 'completed', 'cancelled')", name: "visits_status"
      t.check_constraint "(timing = 'anytime') = (starts_at IS NULL) AND (timing = 'window') = (window_ends_at IS NOT NULL)", name: "visits_times"
      t.check_constraint "duration_minutes BETWEEN 5 AND 1440", name: "visits_duration"
    end
    add_index :visits, :uid, unique: true
    add_index :visits, %i[business_id scheduled_on]
    add_index :visits, %i[job_id scheduled_on]

    create_table :visit_assignments do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :visit, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :visit_assignments, %i[visit_id user_id], unique: true

    create_table :visit_events do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :visit, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.check_constraint "kind IN ('scheduled', 'rescheduled', 'reassigned', 'cancelled', 'restored', 'started', 'completed', 'reopened')", name: "visit_events_kind"
    end
  end
end
