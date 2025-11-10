import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="feather-icons"
// Initializes Feather icons on page load
export default class extends Controller {
  connect() {
    if (typeof feather !== "undefined") {
      feather.replace()
    }
  }
}

