import { Controller } from "@hotwired/stimulus"

// Below this width the sidebar is a drawer (components.css: .side at min-width 960px).
const NARROW = "(max-width: 959.98px)"

// The staff app's sidebar becomes a drawer below the desktop breakpoint. Closed, the drawer is
// only slid off screen, so it's also inert: keyboard and screen-reader users can't reach its
// links (#456). On desktop it's always shown and never inert.
export default class extends Controller {
  static targets = ["panel", "scrim", "toggle"]

  connect() {
    this.media = window.matchMedia(NARROW)
    this.sync = () => this.syncInert()
    this.media.addEventListener("change", this.sync)
    this.syncInert()
  }

  disconnect() {
    this.media.removeEventListener("change", this.sync)
  }

  open() {
    this.panelTarget.dataset.open = "true"
    this.scrimTarget.hidden = false
    this.toggleTargets.forEach((el) => el.setAttribute("aria-expanded", "true"))
    this.syncInert()
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (this.panelTarget.dataset.open !== "true") return
    const hadFocus = this.panelTarget.contains(document.activeElement)
    this.panelTarget.dataset.open = "false"
    this.scrimTarget.hidden = true
    this.toggleTargets.forEach((el) => el.setAttribute("aria-expanded", "false"))
    this.syncInert()
    if (hadFocus) this.toggleTargets.find((el) => el.getClientRects().length)?.focus()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  syncInert() {
    this.panelTarget.inert = this.media.matches && this.panelTarget.dataset.open !== "true"
  }
}
