import { Controller } from "@hotwired/stimulus"

// PLT-19: a list's one status region, outside the results frame it describes, so a screen reader
// hears every search or filter render (a live region that is itself replaced isn't announced
// reliably). It reads the frame's [data-results-summary] ("6 quotes"), or its empty state's title.
//
//   <p class="sr-only" role="status" data-controller="results-status" data-results-status-frame-value="quote_results"></p>
export default class extends Controller {
  static values = { frame: String }

  connect() {
    this.rendered = (event) => { if (event.target.id === this.frameValue) this.announce(event.target) }
    document.addEventListener("turbo:frame-render", this.rendered)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-render", this.rendered)
  }

  announce(frame) {
    const source = frame.querySelector("[data-results-summary]") || frame.querySelector(".empty-title")
    this.element.textContent = source ? source.textContent.trim().replace(/\s+/g, " ") : ""
  }
}
