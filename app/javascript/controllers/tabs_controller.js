import { Controller } from "@hotwired/stimulus"

// A row of tabs that scrolls sideways on narrow screens: keep the current tab in view.
export default class extends Controller {
  connect() {
    const current = this.element.querySelector("[aria-current=page]")
    if (current) this.element.scrollLeft = current.offsetLeft + current.offsetWidth - this.element.clientWidth + 16 > 0
      ? current.offsetLeft - 16 : 0
  }
}
