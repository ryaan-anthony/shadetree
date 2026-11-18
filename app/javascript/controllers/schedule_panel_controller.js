import { Controller } from "@hotwired/stimulus"

// JOB-03: when a visit's details load beside the calendar, bring them into view (below the
// grid on narrower screens) and move focus to them, so keyboard and screen-reader users land
// on what they opened.
export default class extends Controller {
  show() {
    const heading = this.element.querySelector("h2, h3")
    if (!heading) return
    heading.setAttribute("tabindex", "-1")
    heading.focus({ preventScroll: true })
    this.element.scrollIntoView({ block: "nearest", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
  }
}
