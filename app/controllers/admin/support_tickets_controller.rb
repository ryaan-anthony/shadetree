# OPS-05: asking Shadetree for help. Any member opens a ticket (the page they came from and their
# browser go with it) and sees the business's tickets and their replies.
class Admin::SupportTicketsController < Admin::BaseController
  allow_any_member
  before_action :set_ticket, only: %i[show reply]

  def index
    @tickets = SupportTicket.includes(:opened_by).recent.limit(100)
  end

  def new
    @ticket = SupportTicket.new(category: "question", page: safe_page(params[:from]))
  end

  def create
    attributes = params.require(:support_ticket).permit(:subject, :category, :page)
    @ticket = SupportTicket.open!(opened_by: current_user, subject: attributes[:subject], category: attributes[:category],
                                  page: safe_page(attributes[:page]), browser: request.user_agent.to_s.first(300),
                                  body: params.dig(:support_ticket, :body), files: params.dig(:support_ticket, :files))
    return redirect_to(admin_support_ticket_path(@ticket), notice: "Thanks. We'll reply here and by email.") if @ticket.persisted?

    @body = params.dig(:support_ticket, :body)
    render :new, status: :unprocessable_content
  end

  def show
    @reply = SupportMessage.new
  end

  def reply
    @reply = @ticket.reply_from_member!(current_user, params.dig(:support_message, :body), files: params.dig(:support_message, :files))
    return redirect_to(admin_support_ticket_path(@ticket, anchor: "message-#{@reply.id}"), notice: "Reply sent.") if @reply.persisted?

    render :show, status: :unprocessable_content
  end

  private

  def set_ticket = @ticket = SupportTicket.find_by_param!(params[:id])

  # Only a path in the staff app, never a full URL.
  def safe_page(value)
    path = value.to_s.first(500)
    path.start_with?("/admin") && !path.start_with?("//") ? path : nil
  end
end
