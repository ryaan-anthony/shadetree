# Unconfirmed users can set up their business but can't send anything to clients (ACC-01).
# Every action that emails or texts a client (sending a quote, invoice, reminder) declares:
#
#   before_action :require_confirmed_sender, only: :deliver
#
# The send itself should also check user.can_send_to_clients? where it isn't a request
# (for example a job enqueued by that user).
module ConfirmedSender
  extend ActiveSupport::Concern

  private

  def require_confirmed_sender
    return if current_user&.can_send_to_clients?

    message = "Confirm your email address before sending anything to clients. Check your inbox for the link."
    respond_to do |format|
      format.html { redirect_back_or_to admin_root_path, alert: message }
      format.any { head :forbidden }
    end
  end
end
