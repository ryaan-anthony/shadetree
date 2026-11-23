import { Controller } from "@hotwired/stimulus"

// PLT-22: the kit's file upload (f.file_drop). The page has a plain file field, which uploads
// without JavaScript; this turns its zone into a drop area. The real input stays in the form,
// only visually hidden, so Tab, Enter or Space, the picker and screen readers are the
// browser's own, and a dropped file is put into that input. Before saving it shows the chosen
// file's name, size and preview, and checks the type and size the server checks too.
// Dispatches file-drop:chosen with { file, url, problem } (url: the preview; null with a problem).
// A refused file stays in the input (the server refuses it again on save, as before PLT-22).
export default class extends Controller {
  static targets = ["input", "zone", "prompt", "chosen", "thumb", "name", "size", "clear", "check", "checkLine", "serverError", "announce"]
  static values = { types: String, maxBytes: Number, typeError: String, sizeError: String }

  connect() {
    this.element.dataset.enhanced = ""
    this.promptTarget.hidden = false
    this.serverInvalid = this.inputTarget.getAttribute("aria-invalid") === "true" // a refused upload, said below
    this.describedBy = this.inputTarget.getAttribute("aria-describedby") || ""
    this.show(this.inputTarget.files[0] || null, { quiet: true }) // e.g. a page restored from the back button
  }

  disconnect() {
    this.revoke()
  }

  over(event) {
    if (!this.carriesFiles(event)) return
    event.preventDefault() // lets the file be dropped here
    event.dataTransfer.dropEffect = "copy"
    this.zoneTarget.dataset.over = ""
  }

  // On the window: a file dropped beside the zone would open in the tab and lose the form.
  guard(event) {
    if (!this.carriesFiles(event) || this.zoneTarget.contains(event.target)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "none"
  }

  leave(event) {
    if (!this.zoneTarget.contains(event.relatedTarget)) delete this.zoneTarget.dataset.over
  }

  drop(event) {
    if (!this.carriesFiles(event)) return
    event.preventDefault() // the browser would open the file instead
    delete this.zoneTarget.dataset.over
    const file = event.dataTransfer.files[0]
    if (!file) return
    const transfer = new DataTransfer() // one file, even if several were dropped
    transfer.items.add(file)
    this.inputTarget.files = transfer.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  chosen() {
    this.show(this.inputTarget.files[0] || null)
  }

  clear() {
    this.inputTarget.value = ""
    this.show(null)
    this.inputTarget.focus()
    this.say("No file chosen.")
  }

  show(file, { quiet = false } = {}) {
    this.revoke()
    const problem = file ? this.problem(file) : null
    this.checkTarget.textContent = problem || ""
    this.checkLineTarget.hidden = !problem
    this.inputTarget.setAttribute("aria-invalid", String(problem ? true : !file && this.serverInvalid))
    // The server's refusal was about the last upload: once another file passes, it's out of date.
    const stale = file && !problem && this.hasServerErrorTarget
    if (this.hasServerErrorTarget) this.serverErrorTarget.hidden = stale
    this.inputTarget.setAttribute("aria-describedby", stale ? this.describedBy.split(" ").filter((id) => id !== this.serverErrorTarget.id).join(" ") : this.describedBy)
    this.url = file && !problem ? URL.createObjectURL(file) : null

    this.chosenTarget.hidden = !file
    this.thumbTarget.hidden = !this.url
    if (this.url) this.thumbTarget.src = this.url
    else this.thumbTarget.removeAttribute("src")
    if (file) {
      this.nameTarget.textContent = file.name
      this.sizeTarget.textContent = size(file.size)
      this.clearTarget.setAttribute("aria-label", `Clear ${file.name}`)
      if (!quiet) this.say(problem ? `${file.name}: ${problem}` : `${file.name} chosen, ${size(file.size)}. It's uploaded when you save.`)
    }
    this.dispatch("chosen", { detail: { file, url: this.url, problem } })
  }

  problem(file) {
    if (this.typesValue && !this.typesValue.split(",").includes(file.type)) return this.typeErrorValue
    if (this.maxBytesValue && file.size > this.maxBytesValue) return this.sizeErrorValue
    return null
  }

  carriesFiles(event) {
    return [...(event.dataTransfer?.types || [])].includes("Files")
  }

  revoke() {
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = null
  }

  // What was chosen, or why it's refused, read out once (the check line is only described).
  say(text) {
    this.announceTarget.textContent = ""
    requestAnimationFrame(() => { this.announceTarget.textContent = text })
  }
}

function size(bytes) {
  if (bytes < 1048576) return `${Math.max(1, Math.round(bytes / 1024))} KB`
  return `${(bytes / 1048576).toFixed(1)} MB`
}
