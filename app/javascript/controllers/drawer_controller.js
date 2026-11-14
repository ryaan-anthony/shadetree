import { Controller } from "@hotwired/stimulus"

// The staff app's sidebar becomes a drawer below the desktop breakpoint.
export default class extends Controller {
  static targets = ["panel", "scrim", "toggle"]

  open() {
    this.panelTarget.dataset.open = "true"
    this.scrimTarget.hidden = false
    this.toggleTargets.forEach((el) => el.setAttribute("aria-expanded", "true"))
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (this.panelTarget.dataset.open !== "true") return
    this.panelTarget.dataset.open = "false"
    this.scrimTarget.hidden = true
    this.toggleTargets.forEach((el) => el.setAttribute("aria-expanded", "false"))
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
