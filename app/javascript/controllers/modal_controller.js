import { Controller } from "@hotwired/stimulus"

// Opens and closes a <dialog class="modal">. The native dialog traps focus, closes on Esc
// and returns focus to the trigger.
//
//   <div data-controller="modal">
//     <button data-action="modal#open">Edit</button>
//     <%= modal id: "edit-client", title: "Edit client" do %>…<% end %>
//   </div>
//
// When the trigger is gone by the time the dialog closes (an item in a menu that closed),
// focus goes to the element marked data-modal-target="return" instead of the page body.
export default class extends Controller {
  static targets = ["dialog", "return"]
  static values = { open: Boolean } // open on load (a form the server re-rendered with errors)

  connect() {
    this.restoreFocus = () => {
      if (this.opener?.isConnected && this.opener.checkVisibility()) return
      if (this.hasReturnTarget) this.returnTarget.focus()
    }
    this.dialogTarget.addEventListener("close", this.restoreFocus)
    if (this.openValue && !this.dialogTarget.open) this.dialogTarget.showModal()
  }

  disconnect() {
    this.dialogTarget.removeEventListener("close", this.restoreFocus)
  }

  open(event) {
    event?.preventDefault()
    this.opener = event?.currentTarget
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
