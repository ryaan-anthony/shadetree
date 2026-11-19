# OPS-05: the support inbox. Every business's tickets in one queue, filtered by status,
# category, plan and assignee; each ticket with its business's context beside it. Operators
# assign, reply (the member hears in the app and by email), add internal notes and set the
# status. Every action is audited.
class Ops::TicketsController < Ops::BaseController
  PER_PAGE = 30
  REASON = "operator support inbox (OPS-05)".freeze

  before_action :set_ticket, except: :index

  def index
    @filters = params.permit(:status, :category, :plan, :assignee).to_h.symbolize_keys
    @filters[:status] ||= "unresolved"
    Tenancy.across_businesses(reason: REASON) do
      scope = filtered(SupportTicket.includes(:assignee, business: :plan).recent)
      @total = scope.count
      @page = params[:page].to_i.clamp(1, [ (@total.to_f / PER_PAGE).ceil, 1 ].max)
      @tickets = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    end
    @plans = Plan.order(:position, :id)
    @operators = Operator.active.includes(:user).map(&:user)
  end

  def show
    @messages = in_business { @ticket.messages.includes(:author, files_attachments: :blob).to_a }
    @summary = Ops::BusinessSummary.new(@ticket.business)
    @operators = Operator.active.includes(:user).map(&:user)
  end

  def assign
    assignee = params[:assignee].present? ? Operator.active.find_by(user_id: params[:assignee])&.user : nil
    in_business { @ticket.update!(assignee:) }
    audit!("ticket.assigned", ticket: @ticket.uid, assignee: assignee&.email)
    redirect_to ops_ticket_path(@ticket), notice: assignee ? "Assigned to #{assignee.email}." : "Unassigned."
  end

  def reply
    message = in_business { @ticket.reply_from_operator!(current_user, params[:body], status: params[:status].presence || "waiting") }
    return redirect_to(ops_ticket_path(@ticket, anchor: "reply"), alert: "Write a reply first.") unless message.persisted?

    in_business { SupportNotifier.replied(@ticket, message) }
    audit!("ticket.replied", ticket: @ticket.uid, status: @ticket.status)
    redirect_to ops_ticket_path(@ticket), notice: "Reply sent. #{@ticket.opened_by ? "They'll see it in the app and by email." : ""}".strip
  end

  def note
    message = in_business { @ticket.note!(current_user, params[:body]) }
    return redirect_to(ops_ticket_path(@ticket, anchor: "reply"), alert: "Write the note first.") unless message.persisted?

    audit!("ticket.noted", ticket: @ticket.uid)
    redirect_to ops_ticket_path(@ticket), notice: "Note added. Only operators see it."
  end

  def status
    in_business { @ticket.change_status!(params[:status]) }
    audit!("ticket.status_changed", ticket: @ticket.uid, status: @ticket.status)
    redirect_to ops_ticket_path(@ticket), notice: "Marked #{@ticket.status_label.downcase}."
  end

  private

  def set_ticket
    @ticket = Tenancy.across_businesses(reason: REASON) { SupportTicket.includes(:business, :opened_by).find_by!(uid: params[:id].to_s) }
  end

  def in_business(&) = Tenancy.with_business(@ticket.business, &)

  def audit!(action, **data) = super(action, business: @ticket.business, user: @ticket.opened_by, **data)

  def filtered(scope)
    scope = case @filters[:status]
    when "unresolved" then scope.unresolved
    when *SupportTicket::STATUSES.keys then scope.where(status: @filters[:status])
    else scope
    end
    scope = scope.where(category: @filters[:category]) if SupportTicket::CATEGORIES.key?(@filters[:category])
    scope = scope.joins(:business).where(businesses: { plan_id: @filters[:plan].to_i }) if @filters[:plan].present?
    case @filters[:assignee]
    when "me" then scope.where(assignee: current_user)
    when "none" then scope.where(assignee_id: nil)
    when /\A\d+\z/ then scope.where(assignee_id: @filters[:assignee].to_i)
    else scope
    end
  end
end
