# ACC-06: signing out one of your other browsers from the account page. Its session ends at once
# (its next request goes to sign-in), and remember-me stops working on every browser, so the
# signed-out one can't come back on its own.
class Users::BrowserSessionsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    browser_session = current_user.user_sessions.active.find(params[:id])
    return redirect_to(edit_user_registration_path, alert: "That's this browser. Use Sign out instead.") if browser_session == current_user_session

    browser_session.revoke!
    current_user.forget_me!
    redirect_to edit_user_registration_path, notice: "Signed out of #{browser_session.device_label}."
  end
end
