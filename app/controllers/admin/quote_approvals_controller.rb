# QTE-05: Owners and Admins record an approval the client gave another way (on the phone, in
# person), with who approved and a required note. Recorded with who did it; no client email.
class Admin::QuoteApprovalsController < Admin::BaseController
  requires_permission :office

  def create
    @quote = Quote.find_by_param!(params[:quote_id])
    @quote.record_response!(:approve, by: current_user, **params.expect(quote_response: %i[signer_name message]).to_h.symbolize_keys)
    redirect_to preview_admin_quote_path(@quote), notice: "Quote #{@quote.number} marked approved."
  rescue ActiveRecord::RecordInvalid => error
    # The preview again, with the dialog open on what they typed.
    @approval_form = error.record
    @business = current_business
    @document = @quote.reload
    @preview = true
    render "client_links/show", layout: "client", status: :unprocessable_content
  rescue Quote::NotOpen
    reason = @quote.reload.past_expiry? ? "it has expired" : "it's #{@quote.state_label.downcase}"
    redirect_to preview_admin_quote_path(@quote), alert: "Quote #{@quote.number} can't be marked approved: #{reason}."
  end
end
