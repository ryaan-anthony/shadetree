# BIL-04 (ADR 0021): a business's Stripe customer and subscription, mirrored from Stripe; the
# business's billing history (BIL-04/05, shown to operators); and the Stripe events received,
# by id, so each is processed once (no payload is kept).
class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :stripe_customer_id, :string
    add_index :businesses, :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL"

    create_table :subscriptions do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.string :uid, null: false, index: { unique: true }
      t.string :stripe_subscription_id, null: false, index: { unique: true }
      t.references :plan, foreign_key: true # nil when the price isn't one of our plans
      t.string :interval
      t.string :status, null: false
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.datetime :ended_at
      t.datetime :billing_cycle_anchor
      t.datetime :synced_at # when the state held here was fetched from Stripe
      t.timestamps
    end

    create_table :billing_events do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false, index: { unique: true }
      t.string :kind, null: false
      t.jsonb :details, null: false, default: {}
      t.string :dedupe_key # one entry per Stripe invoice or attempt
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
      t.index %i[business_id occurred_at]
      t.index %i[business_id dedupe_key], unique: true, where: "dedupe_key IS NOT NULL"
    end

    create_table :stripe_events do |t|
      t.string :stripe_event_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.string :stripe_object_id, null: false
      t.string :customer_id
      t.boolean :livemode, null: false, default: false
      t.datetime :stripe_created_at, null: false
      t.datetime :processed_at
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempted_at
      t.datetime :created_at, null: false
      t.index :created_at, where: "processed_at IS NULL", name: "index_stripe_events_unprocessed"
    end
  end
end
