import { Controller } from "@hotwired/stimulus"

// Opens and closes a <dialog class="modal">. The native dialog traps focus, closes on Esc
// and returns focus to the trigger.
//
//   <div data-controller="modal">
//     <button data-action="modal#open">Edit</button>
//     <%= modal id: "edit-client", title: "Edit client" do %>…<% end %>
//   </div>
export default class extends Controller {
  static targets = ["dialog"]
  static values = { open: Boolean } // open on load (a form the server re-rendered with errors)

  connect() {
    if (this.openValue && !this.dialogTarget.open) this.dialogTarget.showModal()
  }

  open(event) {
    event?.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.close()
  }

  // A click on the backdrop lands on the <dialog> itself, not its content.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }
}
