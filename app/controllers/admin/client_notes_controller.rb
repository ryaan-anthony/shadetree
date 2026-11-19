# CLI-05: notes on a client's timeline. Anyone on the office team adds them; only the author
# edits one.
class Admin::ClientNotesController < Admin::BaseController
  requires_permission :office

  before_action :set_client
  before_action :set_note, only: %i[edit update]

  def create
    @note = @client.timeline_notes.new(business: current_business, user: current_user, body: params.dig(:client_note, :body))
    if @note.save
      redirect_to admin_client_path(@client, anchor: "client-timeline"), notice: "Note added."
    else
      redirect_to admin_client_path(@client), alert: "Note #{@note.errors[:body].first}."
    end
  end

  def edit; end

  def update
    if @note.update(body: params.dig(:client_note, :body), edited_at: Time.current)
      redirect_to admin_client_path(@client, anchor: "client-event-#{@note.event&.id}"), notice: "Note saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_client = @client = Client.find_by_param!(params[:client_id])

  def set_note
    @note = @client.timeline_notes.find_by_param!(params[:id])
    redirect_to admin_client_path(@client), alert: "Only the person who wrote a note can edit it." unless @note.editable_by?(current_user)
  end
end
