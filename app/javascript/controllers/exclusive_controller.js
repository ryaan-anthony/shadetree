import { Controller } from "@hotwired/stimulus"

// At most one checked box among the targets, like a radio group that can be left empty.
export default class extends Controller {
  static targets = ["box"]

  pick(event) {
    if (!event.target.checked) return
    this.boxTargets.forEach((box) => { if (box !== event.target) box.checked = false })
  }
}
