# #289: /admin/settings, the one entry point to Settings: the first settings page this member
# can open (Business details for owners and admins, Your data for an export-only role), or the
# "not available" page when there's none. The pages keep their own URLs (SettingsHelper groups them).
class Admin::SettingsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member (it only redirects)
  impersonation :allowed
  allow_any_member

  def show
    first = SettingsHelper.groups_for(current_business, Current.membership, self).first&.last&.first
    return redirect_to(first.path) if first

    render "admin/shared/not_allowed", status: :forbidden
  end
end
