# PAY-04: the Stripe Checkout page an invoice has open, so a second Pay (another tab, a double
# tap) reuses it for the same amount, or expires it before making another; and so recording a
# payment, voiding, revising or disconnecting can expire it. One payment, never two.
class AddCheckoutSessionToInvoices < ActiveRecord::Migration[8.1]
  def change
    change_table :invoices, bulk: true do |t|
      t.string :checkout_session_id
      t.string :checkout_session_url
      t.bigint :checkout_amount_cents
      t.datetime :checkout_expires_at
    end
  end
end
