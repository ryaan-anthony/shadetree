# MKT-02: messages from the marketing site's contact form, newest first, in three tabs: open,
# handled and spam (flagged, nobody was emailed). Deleting needs a fresh code and is audited
# without the sender's details, so the permanent log doesn't keep what was asked to be forgotten.
class Ops::ContactMessagesController < Ops::BaseController
  TABS = { "open" => "Open", "handled" => "Handled", "spam" => "Spam" }.freeze
  PER_PAGE = 50
  MAX_PAGE = 10_000

  before_action :set_message, except: :index
  before_action :require_recent_verification, only: %i[destroy erase]

  def index
    @tab = TABS.key?(params[:tab]) ? params[:tab] : "open"
    @counts = { "open" => ContactMessage.not_spam.unhandled.count, "handled" => ContactMessage.not_spam.handled.count, "spam" => ContactMessage.spam.count }
    scope = { "open" => ContactMessage.not_spam.unhandled, "handled" => ContactMessage.not_spam.handled, "spam" => ContactMessage.spam }.fetch(@tab)
    @page = params[:page].to_i.clamp(1, MAX_PAGE)
    @messages = scope.recent.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @messages.size > PER_PAGE
    @messages = @messages.first(PER_PAGE)
  end

  def show
    @from_sender = ContactMessage.where(email: @message.email).count
  end

  # Marks it handled (answered), or open again.
  def update
    @message.update!(handled_at: params[:handled] == "1" ? Time.current : nil)
    redirect_to ops_contact_message_path(@message), notice: @message.handled_at ? "Marked handled." : "Marked open again."
  end

  def destroy
    @message.destroy!
    audit!("contact_message.deleted", message: @message.uid, spam: @message.spam?)
    redirect_to ops_contact_messages_path(tab: tab_for(@message)), notice: "Message deleted."
  end

  # Someone asked to be forgotten: every message from their address goes (as `contact:erase`).
  def erase
    count = ContactMessage.erase_for!(@message.email)
    audit!("contact_message.erased", count:)
    redirect_to ops_contact_messages_path, notice: "Deleted #{helpers.pluralize(count, "message")} from that address."
  end

  private

  def set_message = @message = ContactMessage.find_by_param!(params[:id])

  def tab_for(message) = message.spam? ? "spam" : (message.handled_at ? "handled" : "open")
end
