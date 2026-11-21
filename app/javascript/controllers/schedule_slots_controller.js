import { Controller } from "@hotwired/stimulus"

// QA #274 (WCAG 2.1.1): the calendar's empty time slots are links to a new visit at that day,
// hour and person. They're one stop in the tab order (a roving tabindex): Tab reaches the
// current slot, the arrow keys move between hours (up, down) and days or people (left,
// right), Home and End go to the first and last hour, and Enter opens it. Without JavaScript
// every slot is in the tab order. Space opens a visit on the grid, as Enter does.
export default class extends Controller {
  static targets = ["slot"]

  connect() {
    this.current = this.slotTargets.find((slot) => slot.dataset.start === "true") || this.slotTargets[0]
    this.slotTargets.forEach((slot) => { slot.tabIndex = slot === this.current ? 0 : -1 })
  }

  keydown(event) {
    const visit = event.target.closest(".cal-visit, .cal-chip")
    if (visit && event.key === " ") {
      event.preventDefault()
      visit.click()
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
    if (this.current) this.current.tabIndex = -1
    this.current = slot
    slot.tabIndex = 0
    slot.focus()
  }

  // A click (or Enter) makes that slot the current one, so Tab comes back to it.
  activate(event) {
    const slot = event.target.closest("[data-schedule-slots-target=slot]")
    if (slot && slot !== this.current) this.select(slot)
  }
}
