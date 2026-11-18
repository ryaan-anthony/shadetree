# PAY-05: a receipt for a payment staff recorded, when they choose to send one (PAY-04's online
# payments will send theirs the same way): what was received, how and when, and what's left.
class PaymentMailer < ClientMailer
  def receipt
    @payment = Payment.find(params[:payment_id])
    @invoice = @payment.invoice
    @link = @invoice.client_link!
    client_mail subject: "Payment received for invoice #{@invoice.number} from #{@business.name}"
  end
end
