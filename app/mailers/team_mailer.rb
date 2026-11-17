# The base for email to a business's office team (Owners and Admins, the `office` permission):
# one email per member, so addresses aren't shared. In-app notifications and per-member
# choices come with NTF-02.
class TeamMailer < ApplicationMailer
  helper FormattingHelper

  # Active, confirmed members who can see clients and quotes; not the person who acted.
  def self.office_members(business, except: nil)
    business.business_users.active.where(role: Permissions.roles_with(:office)).includes(:user).map(&:user)
            .select(&:confirmed?).reject { _1.id == except&.id }
  end
end
