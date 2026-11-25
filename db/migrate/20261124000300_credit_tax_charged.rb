# PAY-08 (B14): each credit keeps the tax the invoice it credits charged on it, per rate, so
# "Credit from INV-x" is exactly what INV-x charged and the invoice's tax isn't rounded again.
class CreditTaxCharged < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_credits, :tax_charged, :jsonb, null: false, default: []
  end
end
