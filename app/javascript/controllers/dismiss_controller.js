import { Controller } from "@hotwired/stimulus"

// Removes an element (a toast) on click, or after `afterValue` ms when it is above zero.
// Errors stay until dismissed so they can be read at any pace.
export default class extends Controller {
  static values = { after: { type: Number, default: 0 } }

  connect() {
    if (this.afterValue > 0) this.timer = setTimeout(() => this.close(), this.afterValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  close() {
    this.element.remove()
  }
}
