import { Turbo } from "@hotwired/turbo-rails"

// data-turbo-confirm="Delete this client?" opens the kit's confirm dialog
// (components/_confirm_dialog) instead of the browser's window.confirm.
// Optional: data-turbo-confirm-button="Delete client" names the confirm button, and
// data-turbo-confirm-variant="destructive" makes it solid red; otherwise it's the Primary (PLT-14).
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
  const variant = sources.map((el) => el?.dataset?.turboConfirmVariant).find(Boolean)
  const button = dialog.querySelector("[data-confirm-button]")
  dialog.querySelector("[data-confirm-message]").textContent = message
  button.textContent = label || "Confirm"
  button.className = variant === "destructive" ? button.dataset.destructiveClass : button.dataset.primaryClass
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
