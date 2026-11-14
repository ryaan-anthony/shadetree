import { Turbo } from "@hotwired/turbo-rails"

// data-turbo-confirm="Delete this client?" opens the kit's confirm dialog
// (components/_confirm_dialog) instead of the browser's window.confirm.
// Optional: data-turbo-confirm-button="Delete client" names the confirm button.
// Turbo hands links with data-turbo-method a generated form, not the link, so remember
// which element the user activated to read its data-turbo-confirm-button.
let lastTrigger = null
document.addEventListener("click", (event) => {
  lastTrigger = event.target.closest?.("[data-turbo-confirm]") || null
}, true)

function confirmWithDialog(message, element, submitter) {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(window.confirm(message))

  const sources = [ submitter, lastTrigger, element ]
  const label = sources.map((el) => el?.dataset?.turboConfirmButton).find(Boolean)
  dialog.querySelector("[data-confirm-message]").textContent = message
  dialog.querySelector("[data-confirm-button]").textContent = label || "Confirm"
  dialog.showModal()

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), { once: true })
  })
}

if (Turbo.config?.forms) {
  Turbo.config.forms.confirm = confirmWithDialog
} else {
  Turbo.setConfirmMethod(confirmWithDialog)
}
