import { Controller } from "@hotwired/stimulus"

// JOB-04: photos from site, one per request, each with its own progress bar. A photo whose
// upload fails (a dropped connection, a bad file) stays in the list with the reason and a
// Retry button; the others carry on. Without this controller the form still posts normally.
export default class extends Controller {
  static targets = ["input", "queue", "list"]
  static values = { url: String }

  connect() {
    this.element.querySelector("[data-photo-upload-fallback]")?.setAttribute("hidden", "")
  }

  choose() {
    const files = [...this.inputTarget.files]
    this.inputTarget.value = ""
    files.forEach((file) => this.queueTarget.append(this.row(file)))
    this.next()
  }

  // One at a time, so a weak connection isn't split between several uploads.
  next() {
    if (this.busy) return
    const row = this.queueTarget.querySelector("[data-state=waiting]")
    if (!row) return
    this.busy = true
    this.send(row).finally(() => { this.busy = false; this.next() })
  }

  send(row) {
    return new Promise((resolve) => {
      const body = new FormData()
      body.append("photos[]", row.file)
      const request = new XMLHttpRequest()
      request.open("POST", this.urlValue)
      request.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name=csrf-token]")?.content)
      request.setRequestHeader("X-Requested-With", "XMLHttpRequest")
      request.upload.onprogress = (event) => {
        if (event.lengthComputable) this.show(row, "sending", `Uploading… ${Math.round((event.loaded / event.total) * 100)}%`, event.loaded / event.total)
      }
      request.onload = () => {
        if (request.status === 201) {
          this.listTarget.insertAdjacentHTML("beforeend", request.responseText)
          row.remove()
        } else {
          // A refused file won't upload on a retry; anything else (a server hiccup) might.
          this.failed(row, request.status === 422 ? request.responseText : "Couldn't upload this photo.", request.status !== 422)
        }
        resolve()
      }
      request.onerror = () => { this.failed(row, "The connection dropped.", true); resolve() }
      this.show(row, "sending", "Uploading…", 0)
      request.send(body)
    })
  }

  retry(event) {
    const row = event.target.closest("[data-state]")
    if (!row.retryable) return row.remove()
    this.show(row, "waiting", "Waiting…", 0)
    this.next()
  }

  failed(row, message, retryable) {
    row.retryable = retryable
    row.querySelector("button").textContent = retryable ? "Retry" : "Dismiss"
    this.show(row, "failed", message.replace(`${row.file.name} `, ""), 0)
  }

  row(file) {
    const row = document.createElement("li")
    row.file = file
    row.className = "rounded-control border border-line p-2 text-sm2"
    row.innerHTML = `<div class="flex items-center gap-2"><div class="min-w-0 flex-1"><span class="block truncate font-medium text-ink"></span>
      <span class="status block text-muted" role="status"></span></div>
      <button type="button" class="btn btn-secondary btn-sm shrink-0" data-action="photo-upload#retry" hidden>Retry</button></div>
      <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-sunken"><div class="bar h-full bg-brand" style="width: 0%"></div></div>`
    row.querySelector("span").textContent = file.name
    this.show(row, "waiting", "Waiting…", 0)
    return row
  }

  show(row, state, text, fraction) {
    row.dataset.state = state
    row.querySelector(".status").textContent = text
    row.querySelector(".bar").style.width = `${Math.round(fraction * 100)}%`
    row.querySelector("button").hidden = state !== "failed"
  }
}
