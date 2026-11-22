# ACC-08: first-time tips: the browser reports one shown or hidden; Help shows them all again;
# Your account turns them off (for this person, in every business). Support viewing as a member
# never marks or changes them.
class Admin::TipsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only # the member's own tips, never marked by support
  allow_any_member

  def update
    return head(:unprocessable_content) unless params[:event].in?(%w[seen dismissed])

    Current.membership.record_tip!(params[:key], params[:event])
    head :no_content
  end

  def reset
    Current.membership.update!(tips: {})
    current_user.update!(tips_off: false)
    redirect_back_or_to admin_root_path, notice: t("guidance.tips.shown_again"), status: :see_other
  end

  def preference
    current_user.update!(tips_off: params[:off].to_s == "true")
    redirect_to edit_user_registration_path, notice: (current_user.tips_off? ? t("guidance.tips.setting_off") : t("guidance.tips.setting_on"))
  end
end
