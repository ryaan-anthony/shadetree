# Accepting an invitation (ACC-03): /invitations/:token
#  - signed in as the invited email: accept with one click
#  - signed in as someone else: explain, offer to sign out
#  - signed out, existing account: sign in, then come back here
#  - signed out, new person: set name and password; accepting confirms the email
class InvitationsController < ApplicationController
  layout "marketing"
  before_action :load_invitation
  rate_limit to: 30, within: 10.minutes, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

  def show
    @existing_account = User.exists?(email: @invitation.email) unless user_signed_in?
    @user = User.new(email: @invitation.email) unless user_signed_in? || @existing_account
    store_location_for(:user, request.fullpath) unless user_signed_in?
  end

  def accept
    return redirect_to(invitation_path(params[:token])) unless user_signed_in? && @invitation.for?(current_user)

    join_and_switch(current_user)
  end

  # New people create their account straight from the invitation.
  def sign_up
    return redirect_to(invitation_path(params[:token])) if user_signed_in? || User.exists?(email: @invitation.email)

    @user = User.new(sign_up_params.merge(email: @invitation.email, confirmed_at: Time.current))
    @user.new_record_from_sign_up = true
    @user.skip_confirmation_notification!
    if @user.save
      sign_in(@user)
      join_and_switch(@user)
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_invitation
    @invitation = Invitation.find_by_token(params[:token])
    return render("invitations/unavailable", status: :not_found) unless @invitation
    return render("invitations/unavailable", status: :gone) unless @invitation.pending?

    @business = @invitation.business
  end

  def join_and_switch(user)
    membership = @invitation.accept!(user)
  rescue Invitation::NotAcceptable
    render "invitations/unavailable", status: :gone
  else
    session[:current_business_id] = membership.business_id
    user.update_column(:last_business_id, membership.business_id)
    redirect_to admin_root_path, notice: "Welcome to #{@business.name}."
  end

  def sign_up_params = params.require(:user).permit(:first_name, :last_name, :password, :terms_of_service)
end
