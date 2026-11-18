import { Controller } from "@hotwired/stimulus"

// Removes an element (a toast) on click, or after `afterValue` ms when it is above zero; the
// wait starts again while the pointer or focus is on it, so it never goes mid-read. Errors
// (and toasts with an action, like Undo) stay until dismissed.
export default class extends Controller {
  static values = { after: { type: Number, default: 0 } }

  connect() {
    this.start()
    this.pause = () => clearTimeout(this.timer)
    this.resume = () => this.start()
    this.element.addEventListener("mouseenter", this.pause)
    this.element.addEventListener("focusin", this.pause)
    this.element.addEventListener("mouseleave", this.resume)
    this.element.addEventListener("focusout", this.resume)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  start() {
    clearTimeout(this.timer)
    if (this.afterValue > 0) this.timer = setTimeout(() => this.close(), this.afterValue)
  }

  close() {
    this.element.remove()
  }
}
