# Payments staff record against an invoice (PAY-05): cash, checks, bank transfers and the like,
# including part payments; and correcting or deleting one, with a reason the history keeps.
# Online payments (PAY-04) are listed on the invoice but can't be changed here.
class Admin::InvoicePaymentsController < Admin::BaseController
  requires_permission :office

  before_action :set_invoice
  before_action :set_payment, only: %i[edit update destroy]

  def new
    return redirect_to(helpers.staff_invoice_path(@invoice), alert: cannot_pay_message) unless @invoice.payable?

    @payment = @invoice.payments.new(currency: @invoice.currency, received_on: current_business.today, payment_method: "check")
    @payment.amount = @invoice.balance
  end

  def create
    @payment = @invoice.record_payment!(by: current_user, **payment_params)
    return render(:new, status: :unprocessable_content) if @payment.errors.any?

    redirect_to admin_invoice_path(@invoice), notice: "#{helpers.money(@payment.amount)} recorded. #{balance_notice}"
  rescue ArgumentError
    redirect_to helpers.staff_invoice_path(@invoice), alert: cannot_pay_message
  end

  def edit; end

  def update
    @invoice.change_payment!(@payment, by: current_user, reason: params[:reason], **payment_params)
    return render(:edit, status: :unprocessable_content) if @payment.errors.any?

    redirect_to admin_invoice_path(@invoice), notice: "Payment changed. #{balance_notice}"
  rescue ArgumentError => error
    @payment.assign_attributes(payment_params)
    @reason_error = error.message
    render :edit, status: :unprocessable_content
  end

  def destroy
    @invoice.delete_payment!(@payment, by: current_user, reason: params[:reason])
    redirect_to admin_invoice_path(@invoice), notice: "Payment deleted. #{balance_notice}"
  rescue ArgumentError => error
    @reason_error = error.message
    render :edit, status: :unprocessable_content
  end

  private

  def set_invoice = @invoice = Invoice.find_by_param!(params[:invoice_id])

  # Only recorded payments are changed here.
  def set_payment
    @payment = @invoice.payments.find_by_param!(params[:id])
    redirect_to admin_invoice_path(@invoice), alert: "Online payments can't be changed here." if @payment.online?
  end

  def payment_params = params.expect(payment: %i[amount received_on payment_method reference note]).to_h.symbolize_keys

  def balance_notice
    @invoice.reload
    @invoice.paid? ? "Invoice #{@invoice.number} is paid in full." : "#{helpers.money(@invoice.balance)} left to pay."
  end

  def cannot_pay_message
    if @invoice.revising? then "Send or discard the changes to invoice #{@invoice.number} before recording a payment."
    elsif @invoice.paid? then "Invoice #{@invoice.number} is already paid in full."
    elsif @invoice.void? then "Invoice #{@invoice.number} is void."
    else "Add something to bill before recording a payment."
    end
  end
end
