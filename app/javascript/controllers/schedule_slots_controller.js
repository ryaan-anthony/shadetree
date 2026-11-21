import { Controller } from "@hotwired/stimulus"

// QA #274 (WCAG 2.1.1): the calendar's empty time slots are links to a new visit at that day,
// hour and person. They're one stop in the tab order (a roving tabindex): Tab reaches the
// current slot, the arrow keys move between hours (up, down) and days or people (left,
// right), Home and End go to the first and last hour, and Enter or Space opens it. The stop sits
// at its column's place in the tab order (among that day's visits). Without JavaScript every
// slot is in the tab order, and the arrow-key help isn't attached. Space opens a visit too.
export default class extends Controller {
  static targets = ["slot"]

  connect() {
    this.current = this.slotTargets.find((slot) => slot.dataset.start === "true") || this.slotTargets[0]
    this.slotTargets.forEach((slot) => { slot.tabIndex = slot === this.current ? 0 : -1 })
  }

  // The help only describes the slots while the keys work; a link is natively draggable, and a
  // drag of a slot would start the browser's own link drag (as visits, schedule_drag_controller).
  slotTargetConnected(slot) {
    slot.setAttribute("aria-describedby", "schedule-slots-help")
    slot.draggable = false
    slot.addEventListener("dragstart", this.noNativeDrag)
  }

  slotTargetDisconnected(slot) {
    slot.removeEventListener("dragstart", this.noNativeDrag)
  }

  noNativeDrag = (event) => event.preventDefault()

  // Focus arriving on a slot some other way (coming back to the calendar, a click) makes it the stop.
  focused(event) {
    const slot = event.target.closest?.("[data-schedule-slots-target=slot]")
    if (slot && slot !== this.current) this.makeCurrent(slot)
  }

  keydown(event) {
    const link = event.target.closest(".cal-visit, .cal-chip, [data-schedule-slots-target=slot]")
    if (link && event.key === " ") {
      event.preventDefault()
      link.click()
      return
    }
    const slot = event.target.closest("[data-schedule-slots-target=slot]")
    if (!slot || event.altKey || event.ctrlKey || event.metaKey) return
    const next = this.neighbour(slot, event.key)
    if (next === undefined) return
    event.preventDefault()
    if (next) this.select(next)
  }

  // The slot an arrow key goes to (null at an edge), or undefined for any other key.
  neighbour(slot, key) {
    const columns = [...new Set(this.slotTargets.map((s) => Number(s.dataset.col)))].sort((a, b) => a - b)
    const col = Number(slot.dataset.col), row = Number(slot.dataset.row)
    const at = (c, r) => this.slotTargets.find((s) => Number(s.dataset.col) === c && Number(s.dataset.row) === r) || null
    const inColumn = this.slotTargets.filter((s) => Number(s.dataset.col) === col)
    const step = (direction) => {
      const c = columns[columns.indexOf(col) + direction]
      return c === undefined ? null : at(c, row)
    }
    switch (key) {
      case "ArrowUp": return at(col, row - 1)
      case "ArrowDown": return at(col, row + 1)
      case "ArrowLeft": return step(-1)
      case "ArrowRight": return step(1)
      case "Home": return inColumn[0]
      case "End": return inColumn[inColumn.length - 1]
      default: return undefined
    }
  }

  select(slot) {
    this.makeCurrent(slot)
    slot.focus()
  }

  makeCurrent(slot) {
    if (this.current) this.current.tabIndex = -1
    this.current = slot
    slot.tabIndex = 0
  }
}
