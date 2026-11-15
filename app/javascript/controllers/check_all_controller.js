import { Controller } from "@hotwired/stimulus"

// Disables the submit button while no box is checked.
export default class extends Controller {
  static targets = ["box", "submit"]

  connect() {
    this.update()
    this.element.addEventListener("change", () => this.update())
  }

  update() {
    if (this.hasSubmitTarget) this.submitTarget.disabled = !this.boxTargets.some((box) => box.checked)
  }
}
