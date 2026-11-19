# CLI-05: notes on a client's timeline. Anyone on the office team adds them; only the author
# edits one.
class Admin::ClientNotesController < Admin::BaseController
  requires_permission :office

  before_action :set_client
  before_action :set_note, only: %i[edit update]

  def create
    @note = @client.timeline_notes.new(business: current_business, user: current_user, body: note_body)
    if @note.save
      redirect_to admin_client_path(@client, anchor: "client-timeline"), notice: "Note added."
    else
      render :new, status: :unprocessable_content # keeps what was typed
    end
  end

  def edit; end

  def update
    @note.body = note_body
    @note.edited_at = Time.current if @note.body_changed?
    if @note.save
      redirect_to admin_client_path(@client, anchor: "client-event-#{@note.event&.id}"), notice: "Note saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_client = @client = Client.find_by_param!(params[:client_id])
  def note_body = params.expect(client_note: [ :body ])[:body]

  def set_note
    @note = @client.timeline_notes.find_by_param!(params[:id])
    redirect_to admin_client_path(@client), alert: "Only the person who wrote a note can edit it." unless @note.editable_by?(current_user)
  end
end
