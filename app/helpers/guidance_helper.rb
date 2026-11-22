# ACC-08: the guided tour, on the page it runs on (Home for the office, My day for the field).
module GuidanceHelper
  TOUR_PAGES = { "admin/dashboard" => :office, "admin/my_day" => :field }.freeze

  def guided_tour_here
    page = TOUR_PAGES[controller_path]
    return unless page && action_name.in?(%w[index show])

    tour = GuidedTour.for(Current.membership, checklist: @checklist)
    tour if tour&.page == page
  end

  # The first-time tip for this page, if there is one for this person (FirstTimeTips). Never on
  # a refusal or a suspended business's page, where it would be used up unseen.
  def first_time_tip_here
    return unless response.status == 200 && !current_business&.suspended?

    FirstTimeTips.for(Current.membership, controller_path, action_name)
  end

  # Help's "Show tips again" and Your account's setting: for people with tips, not for support.
  def tips_for_me? = impersonation.nil? && FirstTimeTips.any_for?(Current.membership)
  def tips_setting? = impersonation.nil? && current_user.business_users.active.any? { FirstTimeTips.any_for?(_1) }

  # Whether this member's tour may be running in a tab (its first run, or a replay just begun),
  # so a tip there checks the tab before showing.
  def tour_maybe_running?
    membership = Current.membership
    membership.present? && (membership.tour_status == "started" || membership.tour_replayed_at&.after?(30.minutes.ago)).present?
  end

  # Support viewing as a member sees the tour but never marks it as seen.
  def record_guidance? = impersonation.nil?
end
