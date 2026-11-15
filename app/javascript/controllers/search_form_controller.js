import { Controller } from "@hotwired/stimulus"

// A filter form that submits itself: after a short pause while typing (queue), or at once
// when a select changes (submit). The form targets a Turbo Frame, so only results refresh.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  // Catch up on typing that happened before this controller loaded (a slow phone, a cold
  // cache): if a box no longer holds what the page rendered, search now.
  connect() {
    const typed = [ ...this.element.querySelectorAll("input[type=search], input[type=text]") ].some((input) => input.value !== input.defaultValue)
    if (typed) this.submit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  queue() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  submit() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }
}
