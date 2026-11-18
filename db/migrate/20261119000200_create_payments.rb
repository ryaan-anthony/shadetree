# PAY-05: money received against an invoice. Recorded by staff (cash, check, bank transfer,
# other) or, from PAY-04, taken online. An invoice's amount_paid_cents is the sum of its
# payments, and paid_at is when the payment that settled it was recorded (its link's end, PLT-12).
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false
      t.references :invoice, null: false, foreign_key: true
      t.string :source, null: false, default: "recorded"
      t.string :payment_method, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false
      t.date :received_on, null: false
      t.string :reference
      t.text :note
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps

      t.index %i[business_id uid], unique: true
      t.index %i[business_id invoice_id]
      t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
      t.check_constraint "source IN ('recorded', 'online')", name: "payments_source"
      t.check_constraint "payment_method IN ('cash', 'check', 'bank_transfer', 'other', 'card')", name: "payments_payment_method"
    end

    add_column :invoices, :paid_at, :datetime
  end
end
