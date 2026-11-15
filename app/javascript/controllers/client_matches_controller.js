import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Suggests existing clients as an email or phone is typed (CLI-01, R4). Posts the visible
// contact values to the matches endpoint (POST, so they stay out of URLs and access logs),
// which answers with a turbo stream updating #client_matches.
export default class extends Controller {
  static targets = ["results", "email", "phone"]
  static values = { url: String }

  // Values already in the form (typed before this connected, or re-rendered after an error).
  connect() {
    this.lastQuery = null
    this.request = 0
    this.load()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request++
  }

  check() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 300)
  }

  async load() {
    const body = new FormData()
    const values = (inputs) => inputs.filter((input) => !input.disabled && !input.closest("[hidden]")).map((input) => input.value.trim())
    values(this.emailTargets).filter((value) => value.includes("@")).forEach((value) => body.append("email[]", value))
    values(this.phoneTargets).filter((value) => value.replace(/\D/g, "").length >= 7).forEach((value) => body.append("phone[]", value))

    const query = new URLSearchParams(body).toString()
    if (query === this.lastQuery) return
    this.lastQuery = query
    const request = ++this.request
    if (query === "") {
      this.resultsTarget.replaceChildren()
      return
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(response.statusText)
      const stream = await response.text()
      if (request === this.request) Turbo.renderStreamMessage(stream)
    } catch {
      // Suggestions are a convenience; saving works without them. Try again on the next change.
      if (request === this.request) this.lastQuery = null
    }
  }
}
