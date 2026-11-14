import { Turbo } from "@hotwired/turbo-rails"

// data-turbo-confirm="Delete this client?" opens the kit's confirm dialog
// (components/_confirm_dialog) instead of the browser's window.confirm.
// Optional: data-turbo-confirm-button="Delete client" names the confirm button.
function confirmWithDialog(message, element, submitter) {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(window.confirm(message))

  const source = submitter || element
  dialog.querySelector("[data-confirm-message]").textContent = message
  dialog.querySelector("[data-confirm-button]").textContent =
    source?.dataset?.turboConfirmButton || element?.dataset?.turboConfirmButton || "Confirm"
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
