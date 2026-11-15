import { Controller } from "@hotwired/stimulus"

// The page's "New client" modal (CLI-01) answering client pickers (CLI-02). A picker asks
// with a cancelable "client-picker:new" window event carrying its id; the first modal on the
// page takes the request (so a page that renders two never opens both), and reports back
// with "quick-create:picked" { requester, client } or "quick-create:closed" { requester }.
export default class extends Controller {
  get dialog() {
    return this.element.querySelector("dialog")
  }

  connect() {
    this.onClose = () => {
      this.dispatch("closed", { detail: { requester: this.requester } })
      this.requester = null
    }
    this.dialog.addEventListener("close", this.onClose)
  }

  disconnect() {
    this.dialog.removeEventListener("close", this.onClose)
  }

  requested(event) {
    if (event.defaultPrevented) return
    event.preventDefault()
    this.requester = event.detail?.requester
    this.dialog.showModal()
  }

  picked(event) {
    this.dispatch("picked", { detail: { requester: this.requester, client: event.detail } })
  }
}
