# Invoices (PAY-01): one from scratch for a client, its page, and the builder, which autosaves
# drafts exactly like the quote builder (the same form, partials and script). Invoices from a
# job or a quote start in JobInvoicesController and QuoteInvoicesController. The list, revising
# and voiding sent invoices come with part 2; sending with PAY-02.
class Admin::InvoicesController < Admin::BaseController
  include DocumentBuilder
  requires_permission :office
  before_action :set_invoice, only: %i[show edit update destroy]
  before_action :require_editable, only: %i[edit update]

  # From scratch, e.g. a walk-in job (?client=<uid> preselects the client).
  def new
    @client = Client.active.find_by(uid: params[:client])
    @invoice = Invoice.new
  end

  def create
    client = Client.active.find_by(uid: params.dig(:invoice, :client).to_s)
    unless client
      @invoice = Invoice.new
      @invoice.errors.add(:client, "Choose a client, or add a new one.")
      return render(:new, status: :unprocessable_content)
    end

    invoice = Invoice.start(client:, created_by: current_user)
    redirect_to edit_admin_invoice_path(invoice)
  end

  def show
    redirect_to(edit_admin_invoice_path(@invoice)) if @invoice.editable?
  end

  def edit; end

  # The builder's autosave and its explicit Save, as for quotes: the whole draft with the
  # lock_version it was rendered from, so a stale tab is refused instead of overwriting.
  def update
    saved = Invoice.transaction do
      @invoice.updated_at = Time.current # always write the row, so its lock_version is checked
      apply_builder_params
      @invoice.save || raise(ActiveRecord::Rollback)
    end
    response.set_header("X-Lock-Version", @invoice.lock_version.to_s)
    respond_to do |format|
      format.turbo_stream { render :update, status: (saved ? :ok : :unprocessable_content) }
      format.html do
        next redirect_to(edit_admin_invoice_path(@invoice), notice: "Invoice #{@invoice.number} saved.") if saved

        render :edit, status: :unprocessable_content
      end
    end
  rescue ActiveRecord::StaleObjectError
    respond_to do |format|
      format.turbo_stream { render :stale, status: :conflict }
      format.html { redirect_to edit_admin_invoice_path(@invoice), alert: "This invoice was changed in another tab or by someone else. Here's the latest version." }
    end
  end

  def destroy
    return redirect_to(admin_invoice_path(@invoice), alert: "Only invoices that were never sent can be deleted.") unless @invoice.deletable?

    back = @invoice.job ? admin_job_path(@invoice.job) : admin_client_path(@invoice.client)
    @invoice.destroy!
    redirect_to back, notice: "Draft invoice #{@invoice.number} deleted."
  end

  private

  def set_invoice = @invoice = Invoice.includes(:client, :property, :job, :quote, line_items: :catalog_item).find_by_param!(params[:id])

  def require_editable
    redirect_to admin_invoice_path(@invoice), alert: "Invoice #{@invoice.number} has been sent, so it can't be edited here." unless @invoice.editable?
  end

  def builder_params
    params.require(:invoice).permit(
      :lock_version, :lines_present, :client, :property, :title, :message, :internal_notes, :terms, :issued_on, :payment_terms, :due_on,
      :prices_include_tax, :discount_kind, :discount_value, tax_rates: [],
      lines: [ %i[key catalog_item name description quantity unit unit_price taxable discount_kind discount_value] ]
    )
  end

  def apply_builder_params
    attrs = builder_params
    @invoice.lock_version = attrs[:lock_version] if attrs.key?(:lock_version)
    # An invoice from a job or quote stays with that client; one from scratch can move.
    change_client(attrs[:client]) if attrs[:client].present? && attrs[:client] != @invoice.client.uid && !@invoice.job && !@invoice.quote
    assign_property(attrs[:property]) if attrs.key?(:property)
    @invoice.assign_attributes(attrs.slice(:title, :message, :internal_notes, :terms, :issued_on, :payment_terms, :prices_include_tax))
    @invoice.due_on = attrs[:due_on] if attrs[:payment_terms] == "custom" && attrs.key?(:due_on)
    @invoice.set_discount(attrs[:discount_kind], attrs[:discount_value]) if attrs.key?(:discount_kind)
    @invoice.tax_rate_list = chosen_tax_rates(attrs[:tax_rates]) if attrs.key?(:tax_rates) && !@client_changed
    @invoice.sync_line_items((attrs[:lines] || {}).values) if attrs.key?(:lines) || attrs[:lines_present]
  end

  def builder_document = @invoice
end
