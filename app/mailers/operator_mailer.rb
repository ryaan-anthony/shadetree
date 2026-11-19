# OPS-01: telling someone about changes to their operator access, so a grant or a two-factor
# change they didn't make doesn't go unnoticed.
class OperatorMailer < ApplicationMailer
  before_action { @user = params[:user] }

  def granted = notify("You have Shadetree operator access")
  def two_factor_enabled = notify("Two-factor is on for your operator access")
  def two_factor_reset = notify("Your operator two-factor was reset")

  private

  def notify(subject)
    @url = ops_root_url
    mail to: @user.email, subject:
  end
end
