import { Controller } from "@hotwired/stimulus"

// Rendered when the inline client form finishes (CLI-01, R3). Announces the client to the
// flow that opened the form, then resets the form for next time.
export default class extends Controller {
  static values = { client: Object, resetUrl: String }

  connect() {
    this.dispatch("picked", { detail: this.clientValue })
    const frame = this.element.closest("turbo-frame")
    if (frame && this.hasResetUrlValue) setTimeout(() => { frame.src = this.resetUrlValue }, 0)
  }
}
