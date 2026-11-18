# PAY-05: a receipt for a payment staff recorded, when they choose to send one (PAY-04's online
# payments will send theirs the same way): what was received, how and when, and what's left.
class PaymentMailer < ClientMailer
  def receipt
    @payment = Payment.find_by(id: params[:payment_id])
    return skip_changed_document(subject: "Payment receipt", error: "The payment was deleted before the receipt went out.") unless @payment

    @invoice = @payment.invoice
    # What was left right after this payment, not when the email goes (a later one may be in).
    paid = @invoice.payments.unscope(:order).where(id: ..@payment.id).sum(:amount_cents)
    @balance = Money.new([ @invoice.total_cents - paid, 0 ].max, @invoice.currency)
    @link = @invoice.client_link!
    client_mail subject: "Receipt for invoice #{@invoice.number} from #{@business.name}"
  end
end
