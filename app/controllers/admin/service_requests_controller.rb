# CLI-04: the request inbox. Requests from the public form (CLI-03) and ones staff log after a
# call or a visit, by status; opening one records who saw it; "Create quote" turns it into a
# draft. Office work: technicians can't see requests.
class Admin::ServiceRequestsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include FollowUpForm # CLI-07
  PER_PAGE = 50

  requires_permission :office
  before_action :set_request, only: %i[show status quote]

  filters_by_location ServiceRequest, only: :index # CAT-07

  def index
    @status = params[:status].presence_in(ServiceRequest::STATUSES) || "new"
    @assignee = params[:assignee].to_s[/\A(mine|unassigned|\d+)\z/] # CLI-07
    filtered = by_assignee(ServiceRequest.all)
    @counts = filtered.group(:status).count
    scope = filtered.where(status: @status)
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @requests = scope.recent.includes(:client, :property, :created_by, :location, follow_up: :user).with_attached_photos.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @seen_by_me = ServiceRequestView.where(user: current_user, service_request_id: @requests.map(&:id)).pluck(:service_request_id).to_set
  end

  def show
    # Turbo prefetches links on hover; only a real visit counts as seeing the request.
    @request.viewed_by!(current_user) unless request.headers["X-Sec-Purpose"] == "prefetch"
    @views = @request.views.includes(:user).order(viewed_at: :desc).to_a
    @note = ServiceRequestNote.new
  end

  def new
    @request = ServiceRequest.new(source: "phone", location: current_membership.document_location)
    @follow_up = start_follow_up(@request)
  end

  # Logged by staff: a client (picked, or added inline), one of their properties, the services,
  # what they need and how they got in touch; and, if someone's picked, who follows it up
  # (CLI-07), with warnings first as on the request page.
  def create
    attrs = params.expect(service_request: [ :client, :property, :source, :description, :timing, :location, { service_ids: [] } ])
    @request = ServiceRequest.new(created_by: current_user, source: attrs[:source], description: attrs[:description], timing: attrs[:timing],
                                  location: picked_location(attrs[:location]))
    @request.client = Client.active.find_by(uid: attrs[:client])
    @request.property = @request.client&.properties&.find_by(uid: attrs[:property])
    @request.services = CatalogItem.active.where(uid: Array(attrs[:service_ids])).map { { "catalog_item_id" => _1.id, "name" => _1.name } }
    @request.errors.add(:client, "Choose a client, or add a new one.") unless @request.client
    fields = follow_up_fields
    assign = fields[:user_id].present?
    @follow_up = start_follow_up(@request).tap { _1.assign_attributes(follow_up_attributes(fields)) if assign }
    valid = @request.client && @request.valid?
    return render(:new, status: :unprocessable_content) unless valid && (!assign || @follow_up.valid?)
    return render(:new, status: :unprocessable_content) if assign && follow_up_warn?(@follow_up)

    ServiceRequest.transaction do
      @request.save!
      RequestFollowUp.assign!(@request, follow_up_attributes(fields), by: current_user) if assign
    end
    redirect_to admin_service_request_path(@request), notice: "Request from #{@request.client.display_name} logged#{" and given to #{@follow_up.user.full_name}" if assign}."
  rescue ActiveRecord::RecordInvalid, RequestFollowUp::NotOpen => error
    # Assigning failed after the checks above (a member removed meanwhile): the transaction
    # rolled the request back too, so the form shows again with everything typed.
    @follow_up.errors.add(:base, error.message.delete_prefix("Validation failed: ")) unless error.respond_to?(:record) && error.record == @follow_up
    render :new, status: :unprocessable_content
  end

  def status
    @request.move_to!(params[:status], by: current_user)
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

  # CLI-07: the inbox's "Assigned to" filter: mine, nobody's, or one member's (by user id).
  def by_assignee(scope)
    case @assignee
    when nil then scope
    when "unassigned" then scope.where.not(id: RequestFollowUp.select(:service_request_id))
    else scope.where(id: RequestFollowUp.where(user_id: @assignee == "mine" ? current_user.id : @assignee.to_i).select(:service_request_id))
    end
  end

  def set_request = @request = ServiceRequest.includes(:client, :property, notes: :user, follow_up: %i[user assigned_by]).find_by_param!(params[:id])
end
