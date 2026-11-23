import { Controller } from "@hotwired/stimulus"

// The kit's menu (PLT-19, ControlsHelper#menu): a disclosure. The button toggles the panel
// (aria-expanded); Escape or a click outside closes it and Tab moves on and closes it; the arrow
// keys, Home and End move between its items.
//
//   <div data-controller="menu" data-action="keydown->menu#keydown focusout->menu#focusout">
//     <button data-menu-target="button" data-action="menu#toggle" aria-expanded="false" aria-controls="m1">…</button>
//     <div id="m1" data-menu-target="menu" class="menu" hidden>…menu-item links and buttons…</div>
//   </div>
export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    document.addEventListener("click", this.outside)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
  }

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.items[0]?.focus()
  }

  close() {
    if (this.menuTarget.hidden) return
    this.menuTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  // Focus left the menu and its button (Tab, or a click elsewhere): close it.
  focusout(event) {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }

  keydown(event) {
    if (this.menuTarget.hidden) {
      if (event.key === "ArrowDown" && event.target === this.buttonTarget) { event.preventDefault(); this.open() }
      return
    }
    const items = this.items
    const index = items.indexOf(document.activeElement)
    const move = { ArrowDown: index + 1, ArrowUp: index - 1, Home: 0, End: items.length - 1 }[event.key]
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      this.buttonTarget.focus()
    } else if (move !== undefined && items.length) {
      event.preventDefault()
      items[(move + items.length) % items.length].focus()
    }
  }

  get items() {
    return Array.from(this.menuTarget.querySelectorAll(".menu-item:not([disabled])"))
  }
}
