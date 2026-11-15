import { Controller } from "@hotwired/stimulus"

// Submits the form a control belongs to (including controls outside the form that name it
// with form="…"), e.g. filter tabs rendered inside a results frame.
export default class extends Controller {
  submit(event) {
    event.target.form?.requestSubmit()
  }
}
