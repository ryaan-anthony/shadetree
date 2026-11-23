# JOB-12: "On my way" from My day or the visit's page: the sheet (a dialog there; this page
# without JavaScript, and to confirm a time with a warning), and sending it. Only someone going
# on the visit, booked for today, while the business sends it; anyone else's visit is "not found".
class Admin::MyVisitOnTheWayController < Admin::BaseController
  # OPS-03: support viewing as a member can look, never tell a client someone's coming.
  impersonation :read_only
  include ConfirmedSender
  requires_permission :field_work
  before_action :set_visit
  before_action :require_offered
  before_action :require_confirmed_sender, only: :create

  def new; end

  def create
    arrives_at = @visit.on_the_way_arrival(minutes: params[:minutes], at: params[:at])
    @warning = @visit.on_the_way_warning(arrives_at)
    # A warning is sent anyway once it's been seen: the sheet shows it beside each choice.
    if @warning && params[:seen_warning] != arrives_at.iso8601
      @arrives_at = arrives_at
      return render :new, status: :unprocessable_content
    end

    sent = @visit.send_on_the_way!(arrives_at, by: current_user)
    redirect_to back_path, notice: sent_notice(sent)
  rescue OnTheWay::Refused => error
    @refused = error.message
    render :new, status: :unprocessable_content
  end

  private

  def set_visit
    @visit = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id })
                  .includes(:business, :assignees, job: %i[client property location]).find_by_param!(params[:my_visit_id])
  end

  def require_offered
    return if @visit.on_the_way_offered_to?(current_user)

    redirect_to admin_my_visit_path(@visit), alert: "On my way is only for a visit booked for today that hasn't started."
  end

  def back_path = params[:from] == "day" ? admin_my_day_path : admin_my_visit_path(@visit)

  def sent_notice(sent)
    time = "about #{@visit.on_the_way_time_label(sent.arrives_at)}"
    case sent.why_not
    when nil then "Sent: #{sent.first ? "you're on the way" : "the new time is"}, arriving #{time}. The client has an email and their visit page says so."
    when "small_change" then "Updated to #{time} on the client's visit page. No new email: that's within #{OnTheWay::UPDATE_EMAIL_MINUTES} minutes of the time they were emailed."
    when "no_email" then "Saved: their visit page says #{time}. They have no email address we can use, so call or text them."
    else "Saved: their visit page says #{time}, but no email went: #{current_business.name} has sent its #{EmailMessage::CLIENT_EMAILS_PER_HOUR} client emails for this hour."
    end
  end
end
