# Client records and properties (CLI-01). The list here is basic; CLI-02 adds search,
# filters and sorting. Technicians see clients only through their visits (field_work).
class Admin::ClientsController < Admin::BaseController
  PER_PAGE = 50

  requires_permission :office
  before_action :set_client, only: %i[show edit update archive restore destroy picked]
  layout -> { inline? ? false : "app" }

  def index
    @showing_archived = params[:archived] == "1"
    scope = (@showing_archived ? Client.archived : Client.active)
    @total_count = scope.count
    @page = params[:page].to_i.clamp(1, [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max)
    @clients = scope.alphabetical.includes(:contact_methods, :properties).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @archived_count = Client.archived.count
  end

  def show; end

  def new
    @client = Client.new
    build_blank_rows
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      return redirect_to picked_admin_client_path(@client, inline: 1) if inline?

      redirect_to admin_client_path(@client), notice: "#{@client.display_name} added."
    else
      build_blank_rows
      render :new, status: :unprocessable_content
    end
  end

  def edit = build_blank_rows

  def update
    if @client.update(client_params)
      redirect_to admin_client_path(@client), notice: "#{@client.display_name} saved."
    else
      build_blank_rows
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    @client.archive!
    redirect_to admin_client_path(@client), notice: "#{@client.display_name} archived. Their history is kept."
  end

  def restore
    @client.restore!
    redirect_to admin_client_path(@client), notice: "#{@client.display_name} restored."
  end

  def destroy
    unless @client.deletable?
      return redirect_to admin_client_path(@client),
                         alert: "#{@client.display_name} has quotes, jobs or invoices, so they can't be deleted. Archive them instead."
    end

    @client.destroy!
    redirect_to admin_clients_path, notice: "#{@client.display_name} deleted."
  end

  # Existing clients sharing an email or phone with the form (R4), as a turbo stream that
  # replaces the form's suggestions. A POST so contact details never appear in URLs.
  def matches
    @inline = inline?
    scope = Client.matching(emails: params[:email], phones: params[:phone]).where.not(uid: params[:except].to_s)
    scope = scope.active if @inline # pickers never offer archived clients
    @matches = scope.includes(:contact_methods, :properties).alphabetical.limit(5)
    render turbo_stream: turbo_stream.update("client_matches", partial: "matches", locals: { matches: @matches, inline: @inline })
  end

  # The end of the inline flow: hands the client back to the picker that opened it (R3).
  def picked
    return render :picked_archived, layout: false if @client.archived?

    render layout: false
  end

  private

  def inline? = params[:inline].present?
  helper_method :inline?

  def set_client = @client = Client.find_by_param!(params[:id])

  def client_params
    params.require(:client).permit(
      :display_name, :company_name, :notes, :tag_list, :tax_exempt,
      contact_methods_attributes: %i[id kind value label position _destroy],
      properties_attributes: %i[id label address_line1 address_line2 city region postal_code country access_notes billing position _destroy]
    )
  end

  # The form always offers an empty email, phone and property to fill in.
  def build_blank_rows
    %w[email phone].each do |kind|
      @client.contact_methods.build(kind:) if @client.contact_methods.none? { _1.kind == kind && !_1.marked_for_destruction? }
    end
    @client.properties.build(country: current_business_country) if @client.properties.reject(&:marked_for_destruction?).empty?
  end

  def current_business_country = current_business.try(:country).presence || "US"
end
