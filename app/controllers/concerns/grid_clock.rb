# CAT-07: the calendar's times are on its clock (the filtered location's zone, else the
# business's); a visit or follow-up keeps its own location's. A drag or a slot sends the grid's
# zone (?grid_zone=), so the same moment can be put on the item's clock.
module GridClock
  extend ActiveSupport::Concern

  private

  # A drag's day and "HH:MM" on the grid's clock (?grid_zone=), on `to`'s clock instead.
  def from_grid_clock(on, at, to:)
    zone = ActiveSupport::TimeZone[params[:grid_zone].to_s] if params[:grid_zone].present?
    zone ? shift_clock(on, at, from: zone, to:) : [ on, at ]
  end

  # A day and "HH:MM" on one clock, as the same moment on another.
  def shift_clock(on, at, from:, to:)
    return [ on, at ] unless at.to_s.match?(/\A\d\d:\d\d/) && from.tzinfo.identifier != to.tzinfo.identifier

    hour, minute = at.to_s.split(":").map { Integer(_1, 10) }
    local = from.local(on.year, on.month, on.day, hour, minute).in_time_zone(to)
    [ local.to_date, local.strftime("%H:%M") ]
  end
end
