import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="submenu"
export default class extends Controller {
  static targets = ["menu", "icon"]

  toggle() {
    if (!this.hasMenuTarget || !this.hasIconTarget) {
      console.warn("Menu or icon target not found")
      return
    }

    if (this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.remove("hidden")
      this.iconTarget.style.transform = "rotate(90deg)"
    } else {
      this.menuTarget.classList.add("hidden")
      this.iconTarget.style.transform = "rotate(0deg)"
    }
  }
}

