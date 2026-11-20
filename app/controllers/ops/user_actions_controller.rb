# OPS-04: helping someone sign in: resend their confirmation email, send a password reset, or
# unlock an account locked after too many wrong passwords. Each is audited.
class Ops::UserActionsController < Ops::BaseController
  before_action :set_user

  def confirmation
    return back(alert: "#{@user.email} is already confirmed.") if @user.confirmed? && @user.unconfirmed_email.blank?

    @user.send_confirmation_instructions
    audit!("user.confirmation_resent", user: @user)
    back(notice: "Confirmation email sent to #{@user.unconfirmed_email.presence || @user.email}.")
  end

  def password_reset
    @user.send_reset_password_instructions
    audit!("user.password_reset_sent", user: @user)
    back(notice: "Password reset email sent to #{@user.email}.")
  end

  def unlock
    return back(alert: "#{@user.email} isn't locked.") unless @user.access_locked?

    @user.unlock_access!
    audit!("user.unlocked", user: @user)
    back(notice: "#{@user.email} can sign in again.")
  end

  private

  def set_user
    @user = User.find(params[:id])
    back(alert: "That account was deleted.") if @user.deleted?
  end

  def back(**flash) = redirect_to(ops_users_path(email: @user.email), **flash)
end
