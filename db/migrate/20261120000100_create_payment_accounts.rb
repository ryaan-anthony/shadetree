# PAY-03: a business's own Stripe account (Connect Standard), connected through Stripe's hosted
# onboarding. One connected account per business at a time (CAT-07: one for all its locations);
# a disconnected one is kept, marked, for the record. Its status is a copy of what Stripe last
# told us (account.updated webhooks, and a fetch on return from onboarding).
class CreatePaymentAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_accounts do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false
      t.string :provider, null: false, default: "stripe"
      t.string :account_id, null: false
      t.string :country
      t.boolean :details_submitted, null: false, default: false
      t.boolean :charges_enabled, null: false, default: false
      t.boolean :payouts_enabled, null: false, default: false
      t.string :disabled_reason
      t.jsonb :requirements_due, null: false, default: []
      t.jsonb :requirements_pending, null: false, default: []
      t.datetime :requirements_deadline
      t.datetime :synced_at
      t.references :connected_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :disconnected_at
      t.string :disconnected_reason
      t.references :disconnected_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps

      t.index %i[business_id uid], unique: true
      t.index :business_id, unique: true, where: "disconnected_at IS NULL", name: "index_payment_accounts_one_connected"
      t.index :account_id, unique: true
      t.check_constraint "disconnected_reason IS NULL OR disconnected_reason IN ('owner', 'provider', 'business_deleted')",
                         name: "payment_accounts_disconnected_reason"
    end
  end
end
