import { Controller } from "@hotwired/stimulus"

// NTF-03: "Start from" in the quote and invoice send forms: choosing a template fills the
// subject and message with its wording for this document (worked out on the server; nothing
// is sent until the form is).
export default class extends Controller {
  static targets = ["select", "subject", "message"]

  pick() {
    const option = this.selectTarget.selectedOptions[0]
    if (!option) return
    this.subjectTarget.value = option.dataset.subject
    this.messageTarget.value = option.dataset.message
  }
}
