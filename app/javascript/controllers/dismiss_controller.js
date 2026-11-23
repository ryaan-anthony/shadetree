import { Controller } from "@hotwired/stimulus"

// Removes an element (a toast) on click, or fades it out after `afterValue` ms when it is above
// zero (PLT-21: success toasts, 10 s). The wait stops while the pointer or focus is on it or the
// tab is hidden, and starts again once none of those holds, so it never goes mid-read or unseen.
// Errors (and toasts with an action, like Undo) stay until dismissed.
const FADE = 300
export default class extends Controller {
  static values = { after: { type: Number, default: 0 } }

  connect() {
    this.pause = () => this.stop()
    this.resume = () => { if (!this.held()) this.start() }
    this.visibility = () => (document.hidden ? this.pause() : this.resume())
    this.element.addEventListener("mouseenter", this.pause)
    this.element.addEventListener("focusin", this.pause)
    // focusout fires before focus lands elsewhere, so check once it has.
    this.element.addEventListener("mouseleave", this.resume)
    this.element.addEventListener("focusout", () => setTimeout(this.resume))
    document.addEventListener("visibilitychange", this.visibility)
    this.resume()
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.visibility)
  }

  held() {
    return document.hidden || this.element.matches(":hover, :focus-within")
  }

  stop() {
    clearTimeout(this.timer)
    this.element.classList.remove("is-leaving")
  }

  start() {
    this.stop()
    if (this.afterValue > 0) this.timer = setTimeout(() => this.fade(), this.afterValue)
  }

  fade() {
    this.element.classList.add("is-leaving")
    this.timer = setTimeout(() => this.close(), FADE)
  }

  close() {
    this.element.remove()
  }
}
