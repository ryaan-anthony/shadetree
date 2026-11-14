import { Controller } from "@hotwired/stimulus"

// A disclosure menu: button toggles, Esc or a click outside closes, arrow keys move focus.
//
//   <div data-controller="menu" class="relative">
//     <button data-menu-target="button" data-action="menu#toggle" aria-expanded="false">…</button>
//     <div data-menu-target="menu" class="menu" hidden>…menu-item links…</div>
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

  keydown(event) {
    const items = this.items
    const index = items.indexOf(document.activeElement)
    if (event.key === "Escape") {
      this.close()
      this.buttonTarget.focus()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      items[(index + 1) % items.length]?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      items[(index - 1 + items.length) % items.length]?.focus()
    }
  }

  get items() {
    return Array.from(this.menuTarget.querySelectorAll(".menu-item:not([disabled])"))
  }
}
