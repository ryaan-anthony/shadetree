import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// NTF-03: "Start from" in the quote and invoice send forms: choosing a template fills the
// subject and message with its wording for this document (worked out on the server; nothing
// is sent until the form is). What's been typed is only replaced after asking.
export default class extends Controller {
  static targets = ["select", "subject", "message"]

  connect() {
    this.applied = [this.subjectTarget.value, this.messageTarget.value]
    this.chosen = this.selectTarget.selectedIndex
  }

  async pick() {
    const option = this.selectTarget.selectedOptions[0]
    if (!option) return
    const edited = this.subjectTarget.value !== this.applied[0] || this.messageTarget.value !== this.applied[1]
    const ask = Turbo.config?.forms?.confirm || ((message) => Promise.resolve(window.confirm(message))) // the kit's dialog
    if (edited && !(await ask("Replace what you've written with this template?"))) {
      this.selectTarget.selectedIndex = this.chosen
      return
    }
    this.subjectTarget.value = option.dataset.subject
    this.messageTarget.value = option.dataset.message
    this.applied = [option.dataset.subject, option.dataset.message]
    this.chosen = this.selectTarget.selectedIndex
  }
}
