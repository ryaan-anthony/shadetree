# PAY-04: clients pay invoices online (Stripe Checkout on the business's connected account).
# An online payment is keyed by its PaymentIntent, so a repeated notification never records it
# twice; refunds and disputes Stripe tells us about are kept on it. Businesses choose whether
# clients may pay part of an invoice; plans carry the platform fee (0 until one is decided).
class AddOnlinePayments < ActiveRecord::Migration[8.1]
  def change
    change_table :payments, bulk: true do |t|
      t.string :provider_payment_id
      t.string :provider_checkout_id
      t.string :method_detail
      t.bigint :refunded_cents, null: false, default: 0
      t.bigint :disputed_cents, null: false, default: 0
      t.string :dispute_status
      t.bigint :platform_fee_cents, null: false, default: 0
      t.index :provider_payment_id, unique: true, where: "provider_payment_id IS NOT NULL"
      t.check_constraint "refunded_cents >= 0 AND refunded_cents <= amount_cents", name: "payments_refund_within_amount"
      t.check_constraint "source = 'online' OR provider_payment_id IS NULL", name: "payments_provider_id_online"
    end
    add_column :businesses, :online_partial_payments, :boolean, null: false, default: false
    add_column :plans, :platform_fee_bps, :integer, null: false, default: 0
    add_check_constraint :plans, "platform_fee_bps BETWEEN 0 AND 1000", name: "plans_platform_fee_bps"
  end
end
