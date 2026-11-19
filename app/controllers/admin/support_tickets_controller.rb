# OPS-05: asking Shadetree for help. Any member opens a ticket (the page they came from and their
# browser go with it) and sees the business's tickets and their replies.
class Admin::SupportTicketsController < Admin::BaseController
  PER_PAGE = 25
  # A person, and a whole business, can only send so much: each message can carry 50 MB of
  # screenshots, and an account doesn't need confirming to ask for help.
  PER_USER_PER_HOUR = 10
  PER_BUSINESS_PER_HOUR = 30

  allow_any_member
  before_action :set_ticket, only: %i[show reply]
  before_action :refuse_files_until_confirmed, only: %i[create reply]
  slow_down = -> { redirect_to admin_support_tickets_path, alert: "That's a lot of messages in a short time. Try again in a little while, or email #{ContactMailer.support_address}." }
  rate_limit to: PER_USER_PER_HOUR, within: 1.hour, by: -> { current_user.id }, only: %i[create reply], with: slow_down
  rate_limit to: PER_BUSINESS_PER_HOUR, within: 1.hour, by: -> { current_business.id }, only: %i[create reply], with: slow_down, name: "business"

  def index
    scope = SupportTicket.includes(:opened_by).recent
    @total = scope.count
    @page = params[:page].to_i.clamp(1, [ (@total.to_f / PER_PAGE).ceil, 1 ].max)
    @tickets = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
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

  def set_ticket
    @ticket = SupportTicket.includes(messages: [ :author, { files_attachments: :blob } ]).find_by_param!(params[:id])
  end

  # Screenshots are uploads, so (as with sending to clients) they need a confirmed account.
  def refuse_files_until_confirmed
    files = params.dig(:support_ticket, :files) || params.dig(:support_message, :files)
    return if current_user.confirmed? || Array(files).compact_blank.empty?

    redirect_back_or_to admin_support_tickets_path, alert: "Confirm your email address to attach screenshots. You can send your message without them."
  end

  # Only a path in the staff app, never a full URL.
  def safe_page(value)
    path = value.to_s.first(500)
    path.start_with?("/admin") && !path.start_with?("//") ? path : nil
  end
end
