# ACC-09: team members' faces and titles on staff pages. The business's memberships, with their
# photos, are loaded once a request, so lists don't query per person.
module TeamHelper
  # { user_id => BusinessUser } for the current business's active members, photos preloaded.
  def team_profiles
    @team_profiles ||= current_business ? current_business.business_users.active.with_attached_photo.includes(:user).index_by(&:user_id) : {}
  end

  # The membership of someone on the page: an active member from the list above, else (a
  # deactivated member on past work, which is rare) looked up on its own.
  def team_profile(user)
    team_profiles.fetch(user.id) do
      @other_profiles ||= {}
      @other_profiles.fetch(user.id) { @other_profiles[user.id] = current_business&.business_users&.with_attached_photo&.find_by(user_id: user.id) }
    end
  end

  # A user's photo or initials in this business (decorative beside their name by default).
  def user_avatar(user, size: :sm, decorative: true, **attributes)
    member = team_profile(user)
    return member_avatar(member, size:, decorative:, **attributes) if member

    classes = [ ("avatar-#{size}" unless size == :sm), attributes.delete(:class) ].compact.join(" ").presence
    avatar(user.full_name, class: classes, "aria-hidden": true, **attributes)
  end

  def user_title(user) = team_profile(user)&.title
end
