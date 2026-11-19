# OPS-02: internal notes on a business. Any operator adds one; only its author edits or
# deletes it. Each change is audited (the note's text stays out of the log).
class Ops::NotesController < Ops::BaseController
  before_action :set_business
  before_action :set_note, only: %i[edit update destroy]

  def create
    note = @business.operator_notes.new(body: params.dig(:operator_note, :body), author: current_user)
    if note.save
      audit!("business.note_added", business: @business, note: note.id)
      redirect_to ops_business_path(@business, anchor: "notes"), notice: "Note added."
    else
      redirect_to ops_business_path(@business, anchor: "notes"), alert: "Note #{note.errors[:body].to_sentence}."
    end
  end

  def edit; end

  def update
    if @note.update(body: params.dig(:operator_note, :body))
      audit!("business.note_edited", business: @business, note: @note.id)
      redirect_to ops_business_path(@business, anchor: "notes"), notice: "Note saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @note.destroy!
    audit!("business.note_deleted", business: @business, note: @note.id)
    redirect_to ops_business_path(@business, anchor: "notes"), notice: "Note deleted."
  end

  private

  def set_business = @business = Business.find_by!(uid: params[:business_id].to_s)

  # Someone else's note is "not found" for editing.
  def set_note
    @note = @business.operator_notes.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @note.written_by?(current_user)
  end
end
