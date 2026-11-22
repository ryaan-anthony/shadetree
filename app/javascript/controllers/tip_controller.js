import { Controller } from "@hotwired/stimulus"

// ACC-08: a first-time tip. It stays hidden while the guided tour is running in this tab (the
// tour keeps its place in sessionStorage during its sample-quote detour; a place the server says
// can't be running is stale, and dropped). Otherwise it shows, and once the page is actually in
// view the server marks it seen, so it shows once. "Got it" hides it and puts focus on the page's
// heading. Nothing is marked while support views as the member.
const KEEP_FOR = 30 * 60 * 1000

export default class extends Controller {
  static values = { url: String, record: Boolean, scope: String, tour: Boolean }

  connect() {
    this.element.hidden = this.tourRunning
    if (this.element.hidden) return
    if (document.visibilityState === "hidden") {
      this.whenVisible = () => { if (document.visibilityState === "visible") this.seen() }
      document.addEventListener("visibilitychange", this.whenVisible)
    } else {
      this.seen()
    }
  }

  disconnect() {
    if (this.whenVisible) document.removeEventListener("visibilitychange", this.whenVisible)
  }

  seen() {
    if (this.whenVisible) document.removeEventListener("visibilitychange", this.whenVisible)
    this.whenVisible = null
    this.record("seen")
  }

  dismiss() {
    this.record("dismissed")
    const heading = document.querySelector("#main h1")
    heading?.setAttribute("tabindex", "-1")
    heading?.focus({ preventScroll: true })
    this.element.remove()
  }

  get tourRunning() {
    const key = `shadetree:tour:${this.scopeValue}`
    try {
      const kept = JSON.parse(sessionStorage.getItem(key) || "null")
      if (!kept) return false
      if (this.tourValue && Date.now() - kept.at < KEEP_FOR) return true
      sessionStorage.removeItem(key)
      return false
    } catch { return false }
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
