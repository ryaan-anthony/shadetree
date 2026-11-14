import { Controller } from "@hotwired/stimulus"

// Copies a value (e.g. an invitation link) and briefly confirms on the button.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    await navigator.clipboard.writeText(this.sourceTarget.value)
    const original = this.buttonTarget.innerHTML
    this.buttonTarget.textContent = "Copied"
    setTimeout(() => { this.buttonTarget.innerHTML = original }, 1600)
  }
}
