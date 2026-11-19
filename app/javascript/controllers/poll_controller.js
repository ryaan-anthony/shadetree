import { Controller } from "@hotwired/stimulus"

// Reloads a Turbo frame every few seconds while something runs in the background (CLI-06 import
// progress), without reloading the page. When the frame comes back marked done
// (data-poll-done), the whole page is visited once to show the result.
//
//   <turbo-frame id="progress" src="…" data-controller="poll">…</turbo-frame>
export default class extends Controller {
  static values = { every: { type: Number, default: 3000 } }

  connect() {
    this.loaded = () => { if (this.element.querySelector("[data-poll-done]")) window.Turbo.visit(window.location.href, { action: "replace" }) }
    this.element.addEventListener("turbo:frame-load", this.loaded)
    this.timer = setInterval(() => this.element.reload(), this.everyValue)
  }

  disconnect() {
    clearInterval(this.timer)
    this.element.removeEventListener("turbo:frame-load", this.loaded)
  }
}
