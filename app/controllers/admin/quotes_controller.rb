# Quotes (QTE-01): start a draft for a client, build it with autosave, preview it as the
# client will see it, delete a draft. The list and lifecycle grow with QTE-06; sending is
# QTE-04. Technicians can't see quotes (office permission).
class Admin::QuotesController < Admin::BaseController
  requires_permission :office
  include SendsPdf

  before_action :set_quote, only: %i[show edit update destroy preview pdf]
  before_action :require_editable, only: %i[edit update]

  def index
    @quotes = Quote.includes(:client, sends: :email_message).order(created_at: :desc).limit(100)
  end

  # Pick a client to start a draft (?client=<uid> preselects one). Drafts are only created by
  # POST: a GET (or Turbo's hover prefetch) never uses up a quote number.
  def new
    @client = Client.active.find_by(uid: params[:client])
    @quote = Quote.new
  end

  def create
    client = Client.active.find_by(uid: params.dig(:quote, :client))
    return start_for(client) if client

    @quote = Quote.new
    @quote.errors.add(:client, "Choose a client, or add a new one.")
    render :new, status: :unprocessable_content
  end

  def show = redirect_to(edit_admin_quote_path(@quote))

  def edit; end

  # The builder's autosave and its explicit Save. The form always sends the whole draft
  # (every line, in order), with the lock_version it was rendered from; a save from a stale
  # tab is refused instead of overwriting newer work.
  def update
    saved = Quote.transaction do
      # Always write the quote row, so its lock_version is checked and bumped even when only
      # lines changed: a stale tab can't overwrite line edits. Marking it changed first also
      # stops attachments.attach saving the quote early, before everything is validated.
      @quote.updated_at = Time.current
      apply_builder_params
      # A failed save keeps nothing from this request (lines, files), not just the quote row.
      @quote.save || raise(ActiveRecord::Rollback)
    end
    response.set_header("X-Lock-Version", @quote.lock_version.to_s)
    respond_to do |format|
      format.turbo_stream { render :update, status: (saved ? :ok : :unprocessable_content) }
      format.html do
        next redirect_to(edit_admin_quote_path(@quote), notice: "Quote #{@quote.number} saved.") if saved

        render :edit, status: :unprocessable_content
      end
    end
  rescue ActiveRecord::StaleObjectError
    respond_to do |format|
      format.turbo_stream { render :stale, status: :conflict }
      format.html { redirect_to edit_admin_quote_path(@quote), alert: "This quote was changed in another tab or by someone else. Here's the latest version." }
    end
  end

  def destroy
    unless @quote.draft?
      return redirect_to(edit_admin_quote_path(@quote), alert: "Only draft quotes can be deleted.")
    end

    @quote.destroy!
    redirect_to admin_quotes_path, notice: "Draft #{@quote.number} deleted."
  end

  # The client page (QTE-03) exactly as the client will see it, with a preview banner. Not a
  # client view, and works for drafts.
  def preview
    @business = current_business
    @document = @quote
    @preview = true
    render "client_links/show", layout: "client"
  end

  # QTE-02: the PDF. A draft is rendered fresh; a sent quote's stored file is reused.
  def pdf = send_pdf(@quote, back: @quote.editable? ? edit_admin_quote_path(@quote) : admin_quotes_path)

  # The property choices for a client, for the builder's property select.
  def property_options
    @client = Client.find_by_param!(params[:client])
    @selected = params[:selected]
    render layout: false
  end

  private

  def set_quote = @quote = Quote.includes(:client, :property, line_items: :catalog_item).find_by_param!(params[:id])

  def require_editable
    redirect_to admin_quotes_path, alert: "Quote #{@quote.number} can't be edited." unless @quote.editable?
  end

  def start_for(client)
    quote = Quote.start(client:, created_by: current_user)
    redirect_to edit_admin_quote_path(quote, from: ("setup" if from_setup?))
  end

  def builder_params
    params.require(:quote).permit(
      :lock_version, :lines_present, :client, :property, :title, :message, :internal_notes, :terms, :expires_on, :prices_include_tax,
      :discount_kind, :discount_value, tax_rates: [], lines: [ %i[key catalog_item name description quantity unit unit_price taxable discount_kind discount_value] ],
      attachments: []
    )
  end

  def apply_builder_params
    attrs = builder_params
    @quote.lock_version = attrs[:lock_version] if attrs.key?(:lock_version)
    change_client(attrs[:client]) if attrs[:client].present? && attrs[:client] != @quote.client.uid
    assign_property(attrs[:property]) if attrs.key?(:property)
    @quote.assign_attributes(attrs.slice(:title, :message, :internal_notes, :terms, :expires_on, :prices_include_tax))
    @quote.set_discount(attrs[:discount_kind], attrs[:discount_value]) if attrs.key?(:discount_kind)
    # After a client change the ticks were for the old client; change_client chose the taxes.
    @quote.tax_rate_list = chosen_tax_rates(attrs[:tax_rates]) if attrs.key?(:tax_rates) && !@client_changed
    # lines arrives as { "0" => {…}, "1" => {…} } in form order; lines_present marks a form
    # that sent its (possibly empty) list, so removing every line works.
    @quote.sync_line_items((attrs[:lines] || {}).values) if attrs.key?(:lines) || attrs[:lines_present]
    @quote.attach_files(attrs[:attachments]) if attrs[:attachments].present?
  end

  # After a client change, a submitted property only counts if it's the new client's (the
  # selector may already show the new client's properties); otherwise keep the new default.
  def assign_property(uid)
    property = @quote.client.properties.find_by(uid:) if uid.present?
    return if @client_changed && property.nil?

    @quote.property = property
  end

  # Moving a draft to another client resets its property, and its taxes when exemption differs.
  def change_client(uid)
    client = Client.active.find_by(uid:) or return
    exempt_changed = client.tax_exempt != @quote.client.tax_exempt
    @quote.client = client
    @quote.property = client.billing_property || client.properties.first
    @quote.tax_rate_list = TaxRate.for_new_document(client:) if exempt_changed
    @client_changed = true
  end

  # Tax rates the builder ticked, by "name|percent": the business's active rates plus any the
  # quote already had (so an archived rate on an old draft can stay).
  def chosen_tax_rates(keys)
    available = (TaxRate.active.ordered.map(&:to_pricing) + @quote.tax_rate_list).uniq
    wanted = Array(keys).compact_blank
    available.select { wanted.include?(tax_rate_key(_1)) }
  end

  def tax_rate_key(rate) = "#{rate.name}|#{rate.percent.to_d.to_s("F")}"
  helper_method :tax_rate_key
end
