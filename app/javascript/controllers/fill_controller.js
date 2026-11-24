import { Controller } from "@hotwired/stimulus"

// PAY-08's "Apply now" for the quote's discount.
// - fill: Apply all. Fills the field and tells the form it changed, so an autosaving form (the
//   builder) saves it as if it had been typed; submit: send the form too (the create dialog).
// - select: on focus, the amount is selected, so typing replaces it.
// - applied: the amount that applies after a save (the server holds it to the range). It's put in
//   the field only while nobody's typing there: never under the caret, else on blur.
//
//   <div data-controller="fill" data-fill-value-value="all">
//     <input data-fill-target="field" data-action="focus->fill#select blur->fill#settle">
//     <button type="button" data-action="fill#fill">Apply all</button>
//     <span hidden data-fill-target="applied">200.00</span>
//   </div>
export default class extends Controller {
  static targets = ["field", "applied"]
  static values = { value: String, submit: Boolean }

  fill() {
    this.fieldTarget.value = this.valueValue
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.fieldTarget.dispatchEvent(new Event("change", { bubbles: true }))
    if (this.submitValue) this.fieldTarget.form.requestSubmit()
  }

  select(event) {
    event.target.select()
  }

  // A save came back: show what applies, unless someone's typing there.
  appliedTargetConnected() {
    if (document.activeElement !== this.fieldTarget) this.settle()
  }

  // Only a reply to what the field holds now (a reply to an older save waits for the next), so
  // the form never sends the old amount in place of what was typed.
  settle() {
    if (!this.hasAppliedTarget || this.chosen(this.fieldTarget.value) !== this.appliedTarget.dataset.chosen) return
    this.fieldTarget.value = this.appliedTarget.textContent
  }

  // What the server reads the field as: "all", or cents ("" and "0" are both 0).
  chosen(value) {
    const text = value.trim()
    if (text === "all") return "all"
    const cents = Math.round(parseFloat(text.replace(/[$,]/g, "") || "0") * 100)
    return Number.isNaN(cents) ? null : String(cents)
  }
}
