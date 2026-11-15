import { Controller } from "@hotwired/stimulus"

// Add and remove rows of a nested form (accepts_nested_attributes_for).
//
//   <div data-controller="nested-fields">
//     …rows, each with data-nested-fields-target="row" and a _destroy hidden field
//       marked data-nested-fields-target="destroy"…
//     <template data-nested-fields-target="template" data-kind="email">…NEW_RECORD…</template>
//     <div data-nested-fields-target="anchor">
//       <button data-action="nested-fields#add" data-nested-fields-kind-param="email">Add email</button>
//     </div>
//   </div>
export default class extends Controller {
  static targets = ["template", "anchor", "row", "destroy"]

  add({ params: { kind } }) {
    const template = this.templateTargets.find((element) => element.dataset.kind === kind)
    if (!template) return
    const html = template.innerHTML.replace(/NEW_RECORD/g, `${Date.now()}${Math.floor(Math.random() * 1000)}`)
    this.anchorTarget.insertAdjacentHTML("beforebegin", html)
    this.anchorTarget.previousElementSibling?.querySelector("input:not([type=hidden]), textarea")?.focus()
  }

  // New rows are dropped; saved ones are hidden and marked for destruction.
  remove(event) {
    const row = event.target.closest("[data-nested-fields-target=row]")
    if (!row) return
    const destroy = row.querySelector("[data-nested-fields-target=destroy]")
    if (row.querySelector("input[name$='[id]']")) {
      destroy.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
