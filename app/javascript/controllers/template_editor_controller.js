import { Controller } from "@hotwired/stimulus"

// NTF-03: the message template editor. Placeholder buttons insert {{name}} where the cursor
// was (subject or body), and the preview refreshes from the server as you type, so it shows
// exactly what the email will say, problems included.
export default class extends Controller {
  static targets = ["subject", "body", "preview"]
  static values = { url: String }

  connect() {
    this.field = this.bodyTarget
  }

  focus(event) {
    this.field = event.currentTarget
  }

  insert(event) {
    const text = `{{${event.currentTarget.dataset.placeholder}}}`
    const field = this.field
    const start = field.selectionStart ?? field.value.length
    const end = field.selectionEnd ?? start
    field.value = field.value.slice(0, start) + text + field.value.slice(end)
    field.focus()
    field.setSelectionRange(start + text.length, start + text.length)
    this.refresh()
  }

  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 250)
  }

  async load() {
    const body = new FormData(this.element)
    body.delete("_method")
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const request = (this.request = (this.request || 0) + 1)
    const response = await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "text/html" } })
    // Only the newest answer counts, and never a sign-in page after the session ended.
    if (request !== this.request || !response.ok || response.redirected) return
    this.previewTarget.innerHTML = await response.text()
  }
}
