import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mobile-menu"
export default class extends Controller {
  static targets = ["overlay"]

  open() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("hidden")
    }
  }

  close() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
  }

  closeOnOverlayClick(event) {
    // Close if clicking directly on the overlay (not its children)
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }
}

