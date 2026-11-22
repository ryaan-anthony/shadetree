# JOB-04: "My day": the visits the signed-in member is going on, today first (in time order),
# then anything still open from earlier, then the next two weeks. Technicians land here.
# JOB-06: requests they're following up sit among them, at their time (or with the anytime
# ones); a done one stays until they create the quote or pass it back.
#
# MyDay places each on its own location's day (CAT-07).
class Admin::MyDayController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work

  def show
    day = MyDay.new(current_business, current_user)
    @today, @earlier, @upcoming = day.today, day.earlier, day.upcoming
    # QTE-07: drafts they made from requests given to them, until they're sent.
    @quote_drafts = (Quote.own_drafts_for(current_user).includes(:client).order(:created_at, :id).to_a if can?(:quote_requests) && !can?(:office))
  end
end
