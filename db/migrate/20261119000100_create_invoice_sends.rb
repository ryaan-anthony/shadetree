# PAY-02: each time an invoice went to its client, by email or as a link staff copied, as
# quotes record theirs (QTE-04). The first send marks the invoice sent.
class CreateInvoiceSends < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_sends do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :invoice, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :channel, null: false
      t.string :recipient
      t.string :cc
      t.references :email_message, foreign_key: true
      t.integer :revision, null: false, default: 1
      t.timestamps

      t.index %i[business_id invoice_id]
      t.check_constraint "channel IN ('email', 'link')", name: "invoice_sends_channel"
    end
  end
end
