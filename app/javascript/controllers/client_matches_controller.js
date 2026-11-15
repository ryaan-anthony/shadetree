import { Controller } from "@hotwired/stimulus"

// Suggests existing clients as an email or phone is typed (CLI-01, R4) by pointing the
// "client_matches" frame at the matches endpoint.
export default class extends Controller {
  static targets = ["frame", "email", "phone"]
  static values = { url: String }

  check() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 300)
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    const values = (inputs) => inputs.filter((input) => !input.closest("[hidden]")).map((input) => input.value.trim())
    values(this.emailTargets).filter((value) => value.includes("@")).forEach((value) => url.searchParams.append("email[]", value))
    values(this.phoneTargets).filter((value) => value.replace(/\D/g, "").length >= 7).forEach((value) => url.searchParams.append("phone[]", value))
    if (!url.searchParams.has("email[]") && !url.searchParams.has("phone[]")) {
      this.frameTarget.replaceChildren()
      return
    }
    if (this.frameTarget.src !== url.toString()) this.frameTarget.src = url.toString()
  }
}
