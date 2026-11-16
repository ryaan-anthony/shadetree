import { Controller } from "@hotwired/stimulus"

// Reloads a client's property choices (a turbo frame) when the client picker changes, for
// forms other than the quote builder (which has its own): the request form (CLI-04).
//
//   <form data-controller="property-loader" data-property-loader-url-value="…"
//         data-action="client-picker:change->property-loader#load">
//     <turbo-frame id="quote_property" data-property-loader-target="frame">…</turbo-frame>
export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String, name: String }

  load(event) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("client", event.detail.uid)
    url.searchParams.set("name", this.nameValue)
    this.frameTarget.src = url.toString()
  }
}
