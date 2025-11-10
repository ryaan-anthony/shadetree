import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="user-menu"
export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    if (!this.hasMenuTarget) {
      console.warn("User menu element not found")
      return
    }

    this.menuTarget.classList.toggle("hidden")
  }

  close(event) {
    if (!this.hasMenuTarget) return

    // Close menu when clicking outside
    const userMenuButton = event.target.closest("button")

    if (!userMenuButton || !userMenuButton.hasAttribute("data-action")) {
      this.menuTarget.classList.add("hidden")
    }
  }
}

