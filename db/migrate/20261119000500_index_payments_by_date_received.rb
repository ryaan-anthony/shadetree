# INS-01: the dashboard sums the month's payments by date received.
class IndexPaymentsByDateReceived < ActiveRecord::Migration[8.1]
  def change
    add_index :payments, %i[business_id received_on]
  end
end
