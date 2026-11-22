// #289: every button that saves or sends says what it's doing while the request runs
// ("Creating…", "Sending…"), so a slow request never looks like a dead button. Turbo already
// disables the button and puts its label back afterwards; this only gives it the words.
// A button (or its form) can choose its own with data-turbo-submits-with="Approving…".
// Searches and filters and forms Turbo doesn't handle (data-turbo="false", downloads) are left
// alone, since Turbo wouldn't put their label back; so are icon-only buttons (their aria-label
// names them, and words would change their size). The form is aria-busy while it's on its way.
const VERBS = {
  add: "Adding", approve: "Approving", archive: "Archiving", book: "Booking", cancel: "Cancelling",
  complete: "Completing", connect: "Connecting", copy: "Copying", create: "Creating", decline: "Declining",
  delete: "Deleting", duplicate: "Copying", finish: "Finishing", get: "Getting", hide: "Hiding",
  import: "Importing", invite: "Inviting", log: "Saving", make: "Making", mark: "Saving",
  record: "Recording", remove: "Removing", reopen: "Reopening", resend: "Sending", restore: "Restoring",
  revise: "Opening", save: "Saving", schedule: "Scheduling", send: "Sending", set: "Saving",
  start: "Starting", update: "Saving", upload: "Uploading", void: "Voiding"
}

export function submittingLabel(text) {
  const verb = (text || "").trim().split(/\s+/)[0]?.toLowerCase()
  return VERBS[verb] ? `${VERBS[verb]}…` : "One moment…"
}

function turboHandles(form, submitter) {
  const method = (submitter?.getAttribute("formmethod") || form.getAttribute("method") || "get").toLowerCase()
  if (method === "get") return false
  // Searches and filters (some POST, to keep client names out of URLs) answer at once and in place.
  if (form.querySelector("input[type=search]") || submitter?.hasAttribute("aria-pressed")) return false
  return form.closest("[data-turbo='false']") === null && submitter?.dataset.turbo !== "false"
}

document.addEventListener("submit", (event) => {
  const form = event.target
  const submitter = event.submitter
  if (!(form instanceof HTMLFormElement) || !submitter || !turboHandles(form, submitter)) return
  if (submitter.hasAttribute("data-turbo-submits-with") || form.hasAttribute("data-turbo-submits-with")) return
  if (submitter.closest(".menu")) return // menu items close with the menu; the page changes anyway

  const text = (submitter.tagName === "INPUT" ? submitter.value : submitter.textContent).trim()
  if (!text) return // icon-only

  submitter.setAttribute("data-turbo-submits-with", submittingLabel(text))
}, true)

document.addEventListener("turbo:submit-start", (event) => event.target.setAttribute("aria-busy", "true"))
document.addEventListener("turbo:submit-end", (event) => event.target.removeAttribute("aria-busy"))
