import { Controller } from "@hotwired/stimulus"

// QA #274: after a visit is booked or moved (?focus=<visit>), a booking is cancelled
// (?focus=slot-<day>-<hour>-<person>), or the colors are switched (?focus=color), focus goes
// back to that visit (on the grid or the agenda, whichever shows), slot or pressed button,
// rather than to the top of the page. Several keys, comma-separated, are tried in turn (a new
// visit, then the slot it was booked from, if the calendar doesn't show the visit). The
// parameter is then dropped from the address, so a reload doesn't do it again.
export default class extends Controller {
  connect() {
    const url = new URL(window.location.href)
    const keys = (url.searchParams.get("focus") || this.stored() || "").split(",").filter(Boolean)
    if (!keys.length) return
    const candidates = [...this.element.querySelectorAll("[data-schedule-focus]")].filter((element) => element.checkVisibility())
    const target = keys.map((key) => candidates.find((element) => element.dataset.scheduleFocus === key)).find(Boolean)
    if (target) requestAnimationFrame(() => target.focus())
    if (url.searchParams.has("focus")) {
      url.searchParams.delete("focus")
      window.history.replaceState(window.history.state, "", url)
    }
  }

  // A drag reloads the calendar itself (schedule_drag_controller), and leaves its visit here.
  stored() {
    try {
      const key = sessionStorage.getItem("schedule-focus")
      sessionStorage.removeItem("schedule-focus")
      return key
    } catch { return null }
  }
}
