import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="pricing-toggle"
export default class extends Controller {
  static targets = [
    "toggle", "toggleSwitch",
    "monthlyLabel", "annualLabel",
    "soloPrice", "soloSavings",
    "crewPrice", "crewSavings",
    "fleetPrice", "fleetSavings"
  ]

  connect() {
    this.isAnnual = false
  }

  toggle() {
    this.isAnnual = !this.isAnnual
    this.updatePrices()
    this.updateUI()
  }

  updatePrices() {
    if (this.isAnnual) {
      // Annual pricing
      if (this.hasSoloPriceTarget) this.soloPriceTarget.textContent = "$199"
      if (this.hasCrewPriceTarget) this.crewPriceTarget.textContent = "$399"
      if (this.hasFleetPriceTarget) this.fleetPriceTarget.textContent = "$799"

      // Show savings
      if (this.hasSoloSavingsTarget) this.soloSavingsTarget.classList.remove("hidden")
      if (this.hasCrewSavingsTarget) this.crewSavingsTarget.classList.remove("hidden")
      if (this.hasFleetSavingsTarget) this.fleetSavingsTarget.classList.remove("hidden")
    } else {
      // Monthly pricing
      if (this.hasSoloPriceTarget) this.soloPriceTarget.textContent = "$19"
      if (this.hasCrewPriceTarget) this.crewPriceTarget.textContent = "$39"
      if (this.hasFleetPriceTarget) this.fleetPriceTarget.textContent = "$79"

      // Hide savings
      if (this.hasSoloSavingsTarget) this.soloSavingsTarget.classList.add("hidden")
      if (this.hasCrewSavingsTarget) this.crewSavingsTarget.classList.add("hidden")
      if (this.hasFleetSavingsTarget) this.fleetSavingsTarget.classList.add("hidden")
    }
  }

  updateUI() {
    if (this.isAnnual) {
      // Annual selected
      if (this.hasToggleSwitchTarget) {
        this.toggleSwitchTarget.classList.remove("translate-x-1")
        this.toggleSwitchTarget.classList.add("translate-x-6")
      }
      if (this.hasToggleTarget) {
        this.toggleTarget.classList.remove("bg-gray-200")
        this.toggleTarget.classList.add("bg-shadetree-blue")
      }
      if (this.hasMonthlyLabelTarget) {
        this.monthlyLabelTarget.classList.remove("text-gray-900")
        this.monthlyLabelTarget.classList.add("text-gray-500")
      }
      if (this.hasAnnualLabelTarget) {
        this.annualLabelTarget.classList.remove("text-gray-500")
        this.annualLabelTarget.classList.add("text-gray-900")
      }
    } else {
      // Monthly selected
      if (this.hasToggleSwitchTarget) {
        this.toggleSwitchTarget.classList.remove("translate-x-6")
        this.toggleSwitchTarget.classList.add("translate-x-1")
      }
      if (this.hasToggleTarget) {
        this.toggleTarget.classList.remove("bg-shadetree-blue")
        this.toggleTarget.classList.add("bg-gray-200")
      }
      if (this.hasMonthlyLabelTarget) {
        this.monthlyLabelTarget.classList.remove("text-gray-500")
        this.monthlyLabelTarget.classList.add("text-gray-900")
      }
      if (this.hasAnnualLabelTarget) {
        this.annualLabelTarget.classList.remove("text-gray-900")
        this.annualLabelTarget.classList.add("text-gray-500")
      }
    }
  }
}

