# CLI-04: the request inbox. Requests from the public form (CLI-03) and ones staff log after a
# call or a visit, by status; opening one records who saw it; "Create quote" turns it into a
# draft. Office work: technicians can't see requests.
class Admin::ServiceRequestsController < Admin::BaseController
  PER_PAGE = 50

  requires_permission :office
  before_action :set_request, only: %i[show status quote]

  def index
    @status = params[:status].presence_in(ServiceRequest::STATUSES) || "new"
    @counts = ServiceRequest.group(:status).count
    scope = ServiceRequest.where(status: @status)
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @requests = scope.recent.includes(:client, :property, :created_by).with_attached_photos.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @seen_by_me = ServiceRequestView.where(user: current_user, service_request_id: @requests.map(&:id)).pluck(:service_request_id).to_set
  end

  def show
    # Turbo prefetches links on hover; only a real visit counts as seeing the request.
    @request.viewed_by!(current_user) unless request.headers["X-Sec-Purpose"] == "prefetch"
    @views = @request.views.includes(:user).order(viewed_at: :desc).to_a
    @note = ServiceRequestNote.new
  end

  def new
    @request = ServiceRequest.new(source: "phone")
  end

  # Logged by staff: a client (picked, or added inline), one of their properties, the services,
  # what they need and how they got in touch.
  def create
    attrs = params.expect(service_request: [ :client, :property, :source, :description, :timing, { service_ids: [] } ])
    @request = ServiceRequest.new(created_by: current_user, source: attrs[:source], description: attrs[:description], timing: attrs[:timing])
    @request.client = Client.active.find_by(uid: attrs[:client])
    @request.property = @request.client&.properties&.find_by(uid: attrs[:property])
    @request.services = CatalogItem.active.where(uid: Array(attrs[:service_ids])).map { { "catalog_item_id" => _1.id, "name" => _1.name } }
    @request.errors.add(:client, "Choose a client, or add a new one.") unless @request.client
    return render(:new, status: :unprocessable_content) unless @request.client && @request.save

    redirect_to admin_service_request_path(@request), notice: "Request from #{@request.client.display_name} logged."
  end

  def status
    @request.move_to!(params[:status])
    redirect_to admin_service_request_path(@request), notice: "Marked #{@request.status_label.downcase}."
  rescue ArgumentError
    head :unprocessable_content
  end

  def quote
    if @request.client.archived?
      return redirect_to(admin_service_request_path(@request), alert: "#{@request.client.display_name} is archived. Restore them to quote this request.")
    end

    quote = @request.create_quote!(by: current_user)
    redirect_to edit_admin_quote_path(quote), notice: "Draft #{quote.number} from the request. Nothing is sent until you send it."
  end

  private

  def set_request = @request = ServiceRequest.includes(:client, :property, notes: :user).find_by_param!(params[:id])
end
