# Quotes (QTE-01): start a draft for a client, build it with autosave, preview it as the
# client will see it, delete a draft. QTE-06: the list with filters and search, the staff
# quote page with its activity, and archiving, duplicating and extending expiry. Sending is
# QTE-04. Technicians can't see quotes (office permission), except that QTE-07's members who quote
# requests assigned to them build, preview and download their own drafts (OwnQuoteAccess).
class Admin::QuotesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed, reads: %i[search]
  include DocumentBuilder
  PER_PAGE = 50

  requires_permission :office
  include OwnQuoteAccess
  # QTE-07: what a member who quotes their assigned requests can do with their own draft.
  OWN_DRAFT_ACTIONS = %i[show edit update preview pdf reprice].freeze
  allow_any_member only: OWN_DRAFT_ACTIONS
  include SendsPdf
  leaves_session_alone only: :search
  filters_by_location Quote, only: %i[index search] # CAT-07

  before_action :set_quote, only: %i[show edit update destroy preview pdf archive unarchive duplicate extend_expiry revise revision reprice]
  before_action :require_editable, only: %i[edit update reprice]

  # The list, on the "All" tab (or ?filter= from a link). Searching posts to #search, so client
  # names never appear in URLs.
  def index = load_list

  def search
    load_list
    render partial: "results", layout: false
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

  # A draft opens in the builder; anything sent has its own page: status, actions, the
  # document, the client's response and the activity history.
  def show
    return redirect_to(edit_admin_quote_path(@quote)) if @quote.editable?

    @activity = QuoteActivity.for(@quote)
    @sends_by_revision = @quote.sends_by_revision # QA #274: the Revisions list and the responses
  end

  def archive
    @quote.archive!(by: current_user)
    redirect_to admin_quote_path(@quote), notice: "Quote #{@quote.number} archived. It's under Archived in the list."
  rescue ArgumentError => error
    redirect_to helpers.staff_quote_path(@quote), alert: error.message
  end

  def unarchive
    @quote.unarchive!(by: current_user)
    redirect_to admin_quote_path(@quote), notice: "Quote #{@quote.number} restored."
  end

  # A new draft from this quote, for the same client or another.
  def duplicate
    client = params[:client].present? ? Client.active.find_by(uid: params[:client]) : @quote.client
    return redirect_to(helpers.staff_quote_path(@quote), alert: "Choose a client for the copy.") unless client

    copy = @quote.duplicate!(client:, by: current_user)
    redirect_to edit_admin_quote_path(copy), notice: "Draft #{copy.number} copied from #{@quote.number}."
  end

  # QTE-06: reopens a sent quote as the draft of its next revision, in the builder.
  def revise
    @quote.revise!(by: current_user)
    redirect_to edit_admin_quote_path(@quote), notice: "Revision #{@quote.revision} of #{@quote.number}. Your client sees it's being updated until you send it."
  rescue ArgumentError => error
    redirect_to admin_quote_path(@quote), alert: error.message
  end

  # A previous revision, as it was sent, and what changed in the next one.
  def revision
    @revision = @quote.revisions.find_by!(number: params[:number])
    following = @quote.revisions.find_by(number: @revision.number + 1)
    @changes = @revision.changes_to(following&.snapshot || QuoteResponse.snapshot_of(@quote))
  end

  def extend_expiry
    @quote.extend_expiry!(params[:expires_on], by: current_user)
    redirect_to admin_quote_path(@quote), notice: "Quote #{@quote.number} is now valid until #{l(@quote.expires_on)}."
  rescue ArgumentError => error
    redirect_to admin_quote_path(@quote), alert: error.message
  end

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

  # CAT-08: the draft's location's catalog prices and default taxes, when staff accept the offer.
  def reprice
    apply_location_repricing(@quote, edit_admin_quote_path(@quote)) do |changed|
      QuoteEvent.record!(@quote, :repriced, by: current_user, location: @quote.location.name, changed:)
    end
  end

  def destroy
    if !@quote.draft? || @quote.revising?
      return redirect_to(helpers.staff_quote_path(@quote), alert: "Only quotes that were never sent can be deleted.")
    end

    @quote.destroy!
    redirect_to admin_quotes_path, notice: "Draft #{@quote.number} deleted."
  end

  # The client page (QTE-03) exactly as the client will see it, with a preview banner. Not a
  # client view, and works for drafts.
  def preview
    @business = current_business
    @document = @quote
    @contact = @quote.contact # CAT-07
    @preview = true
    render "client_links/show", layout: "client"
  end

  # QTE-02: the PDF. A draft is rendered fresh; a sent quote's stored file is reused.
  def pdf = send_pdf(@quote, back: @quote.editable? ? edit_admin_quote_path(@quote) : admin_quotes_path)

  # The property choices for a client, for the builder's property select.
  def property_options
    @client = Client.find_by_param!(params[:client])
    @selected = params[:selected]
    # The builder's field, the request form's (CLI-04), the job form's (JOB-01) or the invoice builder's (PAY-01).
    @field_name = params[:name].presence_in(%w[quote[property] service_request[property] job[property] invoice[property]]) || "quote[property]"
    render layout: false
  end

  private

  def load_list
    today = current_business.today
    @filter = params[:filter].presence_in(Quote::FILTERS.keys) || "all"
    @query = params[:q].to_s.strip.first(100)
    scope = Quote.filtered(@filter, today:).search(@query)
    @total_count = scope.count
    @totals = scope.group(:currency).sum(:total_cents).map { |currency, cents| Money.new(cents, currency) }
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @quotes = scope.includes(:business, :client, :property, :location, :responses, sends: :email_message).order(created_at: :desc, id: :desc)
                   .offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @views = ClientLink.where(linkable: @quotes).group(:linkable_id).sum(:views_count)
    @counts = Quote.filter_counts(today:) unless request.post? # the tabs (and their counts) are outside the results
    @any_quotes = @total_count.positive? || Quote.exists?
  end

  def set_quote
    scope = reachable_quotes or return # refused
    @quote = scope.includes(:client, :property, line_items: :catalog_item).find_by_param!(params[:id])
  end

  def require_editable
    redirect_to admin_quotes_path, alert: "Quote #{@quote.number} can't be edited." unless @quote.editable?
  end

  def start_for(client)
    quote = Quote.start(client:, created_by: current_user)
    redirect_to edit_admin_quote_path(quote, from: ("setup" if from_setup?))
  end

  def builder_params
    params.require(:quote).permit(
      :lock_version, :lines_present, :client, :property, :location, :title, :message, :internal_notes, :terms, :expires_on, :prices_include_tax,
      :discount_kind, :discount_value, tax_rates: [], lines: [ %i[key catalog_item name description quantity unit unit_price taxable discount_kind discount_value] ],
      attachments: []
    )
  end

  def apply_builder_params
    attrs = builder_params
    @quote.lock_version = attrs[:lock_version] if attrs.key?(:lock_version)
    # A revision stays with its client: its link was sent to them (QTE-06); so does a quote drafted
    # from an assigned request (QTE-07: they see that client only).
    change_client(attrs[:client]) if attrs[:client].present? && attrs[:client] != @quote.client.uid && !@quote.revising? && !own_quotes_only?
    assign_property(attrs[:property]) if attrs.key?(:property)
    @quote.location = picked_location(attrs[:location]) || @quote.location if attrs.key?(:location)
    @location_changed = @quote.location_id_changed? # CAT-08: offer the new location's prices
    @quote.assign_attributes(attrs.slice(:title, :message, :internal_notes, :terms, :expires_on, :prices_include_tax))
    @quote.set_discount(attrs[:discount_kind], attrs[:discount_value]) if attrs.key?(:discount_kind)
    # After a client change the ticks were for the old client; change_client chose the taxes.
    @quote.tax_rate_list = chosen_tax_rates(attrs[:tax_rates]) if attrs.key?(:tax_rates) && !@client_changed
    # lines arrives as { "0" => {…}, "1" => {…} } in form order; lines_present marks a form
    # that sent its (possibly empty) list, so removing every line works.
    @quote.sync_line_items((attrs[:lines] || {}).values) if attrs.key?(:lines) || attrs[:lines_present]
    @quote.attach_files(attrs[:attachments]) if attrs[:attachments].present?
  end

  def builder_document = @quote
end
