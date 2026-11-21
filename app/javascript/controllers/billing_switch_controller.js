import { Controller } from "@hotwired/stimulus"

// Pricing (MKT-01): the Monthly/Yearly switch is radio buttons and CSS, so prices change with no
// script. This only tells screen readers what changed: the status region gets a summary of the
// prices now shown (QA #274, WCAG 4.1.3).
export default class extends Controller {
  static targets = ["status"]
  static values = { monthly: String, yearly: String }

  announce(event) {
    this.statusTarget.textContent = event.target.value === "yearly" ? this.yearlyValue : this.monthlyValue
  }
}
