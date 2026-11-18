import { Controller } from "@hotwired/stimulus"

// JOB-01: the job form's lines. An item picked in the shared catalog picker becomes a new line
// with the item's values (all still editable); "Add item" (nested-fields) adds a blank one.
export default class extends Controller {
  addFromCatalog({ detail: item }) {
    const template = this.element.querySelector("template[data-kind=line]")
    const anchor = this.element.querySelector("[data-nested-fields-target=anchor]")
    if (!template || !anchor) return
    anchor.insertAdjacentHTML("beforebegin", template.innerHTML.replace(/NEW_RECORD/g, `${Date.now()}${Math.floor(Math.random() * 1000)}`))
    const row = anchor.previousElementSibling
    const set = (field, value) => {
      const input = row.querySelector(`[data-line-field=${field}]`)
      if (input) input.value = value ?? ""
    }
    set("catalog", item.uid)
    set("name", item.name)
    set("description", item.description)
    set("unit", item.unit)
    set("price", item.unit_price)
    set("quantity", "1")
    const taxable = row.querySelector("[data-line-field=taxable]")
    if (taxable) taxable.checked = item.taxable !== false
    row.querySelector("[data-line-field=quantity]")?.focus()
  }
}
