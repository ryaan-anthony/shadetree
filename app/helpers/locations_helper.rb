# CAT-07: which location a request, quote, job or invoice belongs to, shown beside it once the
# business has more than one (preload :location on lists).
module LocationsHelper
  def location_badge(record)
    location = record.try(:location) or return
    return unless current_business&.multiple_locations?

    badge(location.name, dot: false, class: "ml-1 align-middle")
  end
end
