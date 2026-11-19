import { Controller } from "@hotwired/stimulus"

// Monthly/annual switch on the pricing page: swaps each price for its data-annual or
// data-monthly value and shows the yearly savings.
export default class extends Controller {
  static targets = ["switch", "knob", "price", "savings", "monthlyLabel"]

  toggle() {
    const annual = this.switchTarget.getAttribute("aria-checked") !== "true"
    this.switchTarget.setAttribute("aria-checked", String(annual))
    this.switchTarget.classList.toggle("bg-shadetree-blue", annual)
    this.switchTarget.classList.toggle("bg-gray-200", !annual)
    this.knobTarget.classList.toggle("translate-x-6", annual)
    this.knobTarget.classList.toggle("translate-x-1", !annual)
    this.monthlyLabelTarget.classList.toggle("text-gray-500", annual)
    this.monthlyLabelTarget.classList.toggle("text-gray-900", !annual)
    this.priceTargets.forEach((price) => { price.textContent = annual ? price.dataset.annual : price.dataset.monthly })
    this.savingsTargets.forEach((savings) => savings.classList.toggle("hidden", !annual))
  }
}
