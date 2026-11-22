import { Controller } from "@hotwired/stimulus"

// ACC-08: a first-time tip. It stays hidden while the guided tour is running in this tab (the
// tour keeps its place in sessionStorage); otherwise it shows, and the server marks it seen, so
// it shows once. "Got it" hides it. Nothing is marked while support views as the member.
export default class extends Controller {
  static values = { url: String, record: Boolean, scope: String }

  connect() {
    if (this.tourRunning) return
    this.element.hidden = false
    this.record("seen")
  }

  dismiss() {
    this.record("dismissed")
    this.element.remove()
  }

  get tourRunning() {
    try { return sessionStorage.getItem(`shadetree:tour:${this.scopeValue}`) !== null } catch { return false }
  }

  record(event) {
    if (!this.recordValue) return
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify({ event }),
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }
}
