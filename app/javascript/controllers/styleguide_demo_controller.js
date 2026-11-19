import { Controller } from "@hotwired/stimulus"

// Styleguide only: a demo form that records that it was submitted instead of posting.
export default class extends Controller {
  submit(event) {
    event.preventDefault()
    this.element.dataset.submitted = "yes"
  }
}
