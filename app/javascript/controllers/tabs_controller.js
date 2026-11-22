import { Controller } from "@hotwired/stimulus"

// A row of tabs that scrolls sideways on narrow screens: keeps the current tab in view. When
// the tabs are a filter form's submit buttons (the quotes list), pressing one also marks it
// pressed and stores its value in the form's hidden field, for later searches and pages.
//
//   <nav class="tabs" data-controller="tabs">…</nav>
//   <form data-controller="tabs"><input type="hidden" data-tabs-target="field">
//     <nav class="tabs" data-tabs-target="row"><button data-action="tabs#press" …></nav></form>
export default class extends Controller {
  static targets = ["row", "field"]

  connect() {
    // Turbo disables a submit button while its request runs, which drops focus to the page;
    // put it back on the tab that was pressed once the results arrive.
    this.refocus = () => {
      if (this.pressed?.isConnected && (document.activeElement === document.body || !document.activeElement)) this.pressed.focus()
      this.pressed = null
    }
    document.addEventListener("turbo:frame-render", this.refocus)
    const row = this.hasRowTarget ? this.rowTarget : this.element
    const current = row.querySelector("[aria-current=page], [aria-current=true], [aria-pressed=true]")
    if (current && current.offsetLeft + current.offsetWidth > row.clientWidth) row.scrollLeft = current.offsetLeft - 16
  }

  disconnect() {
    document.removeEventListener("turbo:frame-render", this.refocus)
  }

  press(event) {
    const pressed = event.currentTarget
    this.pressed = pressed
    if (this.hasFieldTarget) this.fieldTarget.value = pressed.value
    this.rowTarget.querySelectorAll("[aria-pressed]").forEach((tab) => tab.setAttribute("aria-pressed", String(tab === pressed)))
  }
}
