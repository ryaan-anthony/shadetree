import { Controller } from "@hotwired/stimulus"

// NTF-04: the automation form shows only the conditions and actions that fit the chosen trigger
// (each option lists the subjects it fits in data-subjects), and opens an option's own fields
// when its box is ticked. Hidden options are disabled so they aren't sent.
export default class extends Controller {
  static targets = ["trigger", "option"]

  connect() { this.refresh() }

  refresh() {
    const subject = this.triggerTarget.selectedOptions[0]?.dataset.subject
    this.optionTargets.forEach((option) => {
      const fits = option.dataset.subjects.split(" ").includes(subject)
      option.hidden = !fits
      const box = option.querySelector("input[type=checkbox]")
      option.querySelectorAll("input, select").forEach((input) => {
        input.disabled = !fits || (input !== box && box && !box.checked)
      })
      const details = option.querySelector("[data-option-details]")
      if (details) details.hidden = !(fits && (!box || box.checked))
    })
  }
}
