import { Controller } from "@hotwired/stimulus"

// QA #274: after a visit is booked or moved (?focus=<visit>), or the colors are switched
// (?focus=color), focus goes back to that visit (on the grid or the agenda, whichever shows)
// or the pressed button, rather than to the top of the page. The parameter is then dropped
// from the address, so a reload doesn't do it again.
export default class extends Controller {
  connect() {
    const url = new URL(window.location.href)
    const key = url.searchParams.get("focus") || this.stored()
    if (!key) return
    const target = [...this.element.querySelectorAll("[data-schedule-focus]")]
      .find((element) => element.dataset.scheduleFocus === key && element.checkVisibility())
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
