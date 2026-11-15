import { Controller } from "@hotwired/stimulus"

// Shows the free-text unit field only when "custom" is chosen.
export default class extends Controller {
  static targets = ["select", "input"]

  toggle() {
    const custom = this.selectTarget.value === "custom"
    this.inputTarget.hidden = !custom
    if (custom) this.inputTarget.focus()
  }
}
