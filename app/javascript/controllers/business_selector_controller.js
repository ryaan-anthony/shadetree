import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="business-selector"
export default class extends Controller {
  static targets = ["select", "selectedOption"]
  static values = {
    switchUrl: String
  }

  connect() {
    console.log("Business selector initialized")
    this.resetToCurrentBusiness()
  }

  resetToCurrentBusiness() {
    const selectedOption = this.selectTarget.querySelector("option[selected]")
    if (selectedOption) {
      this.selectTarget.value = selectedOption.value
      console.log("Set selector to:", selectedOption.value, selectedOption.text)
    }
  }

  change(event) {
    const value = event.target.value
    console.log("Business selector changed to:", value)

    if (value === "new") {
      console.log("Navigating to new business page")
      window.location.href = "/admin/business/new"
    } else if (value && value !== "Setting up business...") {
      this.switchBusiness(value)
    }
  }

  async switchBusiness(businessId) {
    console.log("Switching to business ID:", businessId)

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    if (!csrfToken) {
      console.error("CSRF token not found")
      alert("Security token missing. Please refresh the page.")
      return
    }

    // Disable selector during switch
    this.selectTarget.disabled = true

    try {
      const response = await fetch(this.switchUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ business_id: businessId })
      })

      console.log("Switch response status:", response.status)
      const data = await response.json()
      console.log("Switch response data:", data)

      if (data.success) {
        console.log("Successfully switched to:", data.business.name)
        window.location.reload()
      } else {
        console.error("Failed to switch business:", data.error)
        alert("Failed to switch business: " + (data.error || "Unknown error"))
        this.selectTarget.disabled = false
        this.resetToCurrentBusiness()
      }
    } catch (error) {
      console.error("Error switching business:", error)
      alert("An error occurred while switching businesses. Please try again.")
      this.selectTarget.disabled = false
      this.resetToCurrentBusiness()
    }
  }
}

