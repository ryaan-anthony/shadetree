# ACC-08: records where a member is with the guided tour: the browser reports each move (JSON),
# and Skip on the offer is a plain form. Support viewing as a member never marks it.
class Admin::ToursController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only # the member's own progress, never marked by support
  allow_any_member

  def update
    tour = GuidedTour.for(Current.membership, checklist: SetupChecklist.new(current_business, membership: Current.membership))
    stop = params[:stop].to_s
    return head(:unprocessable_content) unless tour && (tour.keys.include?(stop) || stop == GuidedTour::OFFER)

    Current.membership.record_tour!(params[:event], stop)
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to (tour.page == :field ? admin_my_day_path : admin_root_path), notice: (t("guidance.tour.offer.skipped") if stop == GuidedTour::OFFER) }
    end
  end
end
