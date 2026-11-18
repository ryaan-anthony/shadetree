import { Controller } from "@hotwired/stimulus"

// JOB-01: choosing a catalog item on a job line fills the line from it (name, description,
// unit, price and taxable); the fields stay editable. Choosing "A custom item" changes nothing.
export default class extends Controller {
  static targets = ["name", "description", "quantity", "unit", "price", "taxable"]

  fill(event) {
    const option = event.target.selectedOptions[0]
    if (!option?.value) return
    const { name, description, unit, price, taxable } = option.dataset
    this.nameTarget.value = name || ""
    this.descriptionTarget.value = description || ""
    this.unitTarget.value = unit || ""
    this.priceTarget.value = price || ""
    this.taxableTarget.checked = taxable === "true"
    if (!this.quantityTarget.value) this.quantityTarget.value = "1"
  }
}
