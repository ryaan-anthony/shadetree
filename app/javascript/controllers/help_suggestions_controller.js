import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// OPS-06: on the ticket form, offers help articles as the subject is typed. Posts the subject
// and the page the question comes from (POST, so they stay out of URLs and access logs); the
// answer is a turbo stream replacing #help-suggestions.
export default class extends Controller {
  static targets = ["subject", "page"]
  static values = { url: String }

  connect() {
    this.lastQuery = this.query
    this.request = 0
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request++
  }

  get query() {
    return this.subjectTarget.value.trim()
  }

  check() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 400)
  }

  async load() {
    const query = this.query
    if (query === this.lastQuery) return
    this.lastQuery = query
    const request = ++this.request
    const body = new FormData()
    body.append("subject", query)
    body.append("page", this.hasPageTarget ? this.pageTarget.value : "")
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
      // Suggestions are a convenience; the question sends without them. Try again on the next change.
      if (request === this.request) this.lastQuery = null
    }
  }
}
