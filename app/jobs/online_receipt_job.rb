# PAY-04: a receipt for an online payment that waited for the hourly email cap
# (OnlinePayments.send_receipt), tried again; it waits again if the cap is still reached.
class OnlineReceiptJob < ApplicationJob
  queue_as :default

  def perform(payment_id)
    payment = Payment.find_by(id: payment_id) or return
    return if EmailMessage.exists?(kind: "payment_receipt", related: payment)

    OnlinePayments.send_receipt(payment)
  end
end
