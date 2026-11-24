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
    this.resized = () => { if (!this.menuTarget.hidden) this.keepOnScreen() }
    window.addEventListener("resize", this.resized)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    window.removeEventListener("resize", this.resized)
  }

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.keepOnScreen()
    this.items[0]?.focus()
  }

  // A menu opens towards the side its alignment says; where that would run off the screen (a
  // button near a phone's edge), it shifts back on, in one move from one measurement. It moves
  // again if the window is resized while it's open (a phone turned round).
  keepOnScreen() {
    const menu = this.menuTarget
    const style = menu.style
    style.left = style.right = style.maxWidth = ""
    const margin = 8
    const box = menu.getBoundingClientRect()
    const shift = box.left < margin ? margin - box.left : Math.min(0, document.documentElement.clientWidth - margin - box.right)
    if (!shift) return
    // left is measured from the inside of the menu's positioned ancestor (its padding edge). Every
    // caller wraps the menu in its own non-scrolling relative box, so its scrollLeft is always 0.
    const parent = menu.offsetParent
    const origin = parent ? parent.getBoundingClientRect().left + parent.clientLeft : 0
    style.right = "auto"
    style.left = `${box.left + shift - origin}px`
    // Shifted right off the left edge, a menu at its width cap can still pass the right margin
    // (a desktop scrollbar narrows the page): hold it inside both margins.
    const room = document.documentElement.clientWidth - 2 * margin
    if (box.width > room) style.maxWidth = `${room}px`
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
      event.stopPropagation() // Escape closes the innermost layer only (a menu in the drawer)
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
