import { Controller } from "@hotwired/stimulus"

// Fills a field with a value and tells the form it changed, so an autosaving form (the builder)
// saves it as if it had been typed: PAY-08's "Apply all" for the quote's discount.
//
//   <div data-controller="fill" data-fill-value-value="all">
//     <input data-fill-target="field"> <button type="button" data-action="fill#fill">Apply all</button>
//   </div>
export default class extends Controller {
  static targets = ["field"]
  static values = { value: String }

  fill() {
    this.fieldTarget.value = this.valueValue
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.fieldTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
