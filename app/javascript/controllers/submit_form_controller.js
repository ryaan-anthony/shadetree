import { Controller } from "@hotwired/stimulus"

// Submits the form a control belongs to (including controls outside the form that name it
// with form="…"), e.g. the clients list's Active/Archived tabs, kept outside its results frame
// so a search result rendering mid-click can't replace them (#464).
export default class extends Controller {
  submit(event) {
    event.target.form?.requestSubmit()
  }
}
