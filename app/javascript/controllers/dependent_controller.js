import { Controller } from "@hotwired/stimulus"

// Turns off the fields that only matter while a checkbox is ticked (the request form's "Let
// search engines find…" needs "Take requests online"). Disabled fields aren't sent, so the
// server keeps what they had; it ignores them too when the box is off.
//
//   <div data-controller="dependent">
//     <input type="checkbox" data-dependent-target="source" data-action="dependent#update">
//     <div data-dependent-target="field">…inputs…</div>
//   </div>
export default class extends Controller {
  static targets = ["source", "field"]

  connect() {
    this.update()
  }

  update() {
    const on = this.sourceTarget.checked
    this.fieldTargets.forEach((field) => {
      field.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = !on })
    })
  }
}
