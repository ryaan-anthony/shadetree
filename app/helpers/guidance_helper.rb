# ACC-08: the guided tour, on the page it runs on (Home for the office, My day for the field).
module GuidanceHelper
  TOUR_PAGES = { "admin/dashboard" => :office, "admin/my_day" => :field }.freeze

  def guided_tour_here
    page = TOUR_PAGES[controller_path]
    return unless page && action_name.in?(%w[index show])

    tour = GuidedTour.for(Current.membership, checklist: @checklist)
    tour if tour&.page == page
  end

  # The first-time tip for this page, if there is one for this person (FirstTimeTips).
  def first_time_tip_here = FirstTimeTips.for(Current.membership, controller_path, action_name)

  # Support viewing as a member sees the tour but never marks it as seen.
  def record_guidance? = impersonation.nil?
end
