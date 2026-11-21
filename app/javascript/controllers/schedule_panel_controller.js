import { Controller } from "@hotwired/stimulus"

// JOB-03: when a visit's details (or a new visit's job choice, QA #274) load beside the
// calendar, bring them into view (below the grid on narrower screens) and move focus to them,
// so keyboard and screen-reader users land on what they opened. Its Close (or Cancel) button
// empties the panel and puts focus back on the visit or slot that opened it.
export default class extends Controller {
  static targets = ["close"]

  connect() {
    this.remember = (event) => {
      const opener = event.target.closest?.(`a[data-turbo-frame="${this.element.id}"]`)
      if (opener) this.opener = opener
    }
    document.addEventListener("click", this.remember, true)
  }

  disconnect() {
    document.removeEventListener("click", this.remember, true)
  }

  // The buttons only make sense beside the calendar, not on the visit's own page (phones).
  closeTargetConnected(button) {
    button.hidden = false
  }

  show() {
    const heading = this.element.querySelector("h2, h3")
    if (!heading) return
    heading.setAttribute("tabindex", "-1")
    heading.focus({ preventScroll: true })
    this.element.scrollIntoView({ block: "nearest", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
  }

  close() {
    this.element.removeAttribute("src")
    this.element.replaceChildren()
    // The opener can be gone (the calendar reloaded meanwhile): then the grid's current slot.
    const opener = this.opener?.isConnected ? this.opener : null
    const target = opener || document.querySelector("#schedule-grid [data-schedule-slots-target=slot][tabindex='0']")
    target?.focus()
    this.opener = null
  }
}
