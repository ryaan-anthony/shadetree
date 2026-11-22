import { Controller } from "@hotwired/stimulus"

// JOB-04: photos from site, one per request, each with its own progress bar.
// - A photo that fails stays in the list with the reason. Retry for a dropped connection or
//   a server hiccup; Dismiss for a file the server refused.
// - Photos that failed because the connection dropped go again on their own when the phone
//   is back online.
// - Leaving the page while photos are waiting asks first.
// Without this controller the form still posts normally.
const STALL_MS = 45_000 // no upload progress for this long: give up on this try
const PAUSED = "paused" // signed out: nothing more is sent until someone taps Retry

export default class extends Controller {
  static targets = ["queue", "list", "announce"]
  static classes = ["retry"] // the kit's classes for the Retry button (button_classes, PLT-14)
  static values = { url: String, count: Number, noun: { type: String, default: "visit" } }

  connect() {
    this.element.querySelector("[data-photo-upload-fallback]")?.setAttribute("hidden", "")
  }

  disconnect() {
    this.leaving = true
    this.request?.abort()
    clearTimeout(this.stall)
  }

  choose(event) {
    const files = [...event.target.files]
    event.target.value = ""
    files.forEach((file) => this.queueTarget.append(this.row(file)))
    if (files.length > 1) this.say(`${files.length} photos waiting to upload.`)
    this.next()
  }

  // One at a time, so a weak connection isn't split between several uploads.
  next() {
    if (this.busy || this.state === PAUSED) return
    const row = this.queueTarget.querySelector("[data-state=waiting]")
    if (!row) return
    this.busy = true
    this.send(row).finally(() => { this.busy = false; this.next() })
  }

  send(row) {
    return new Promise((resolve) => {
      const body = new FormData()
      body.append("photos[]", row.file)
      const request = this.request = new XMLHttpRequest()
      const done = (fn) => () => { clearTimeout(this.stall); this.request = null; if (!this.leaving) fn(); resolve() }
      const watch = () => { clearTimeout(this.stall); this.stall = setTimeout(() => { row.stalled = true; request.abort() }, STALL_MS) }

      request.open("POST", this.urlValue)
      request.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name=csrf-token]")?.content)
      request.setRequestHeader("X-Requested-With", "XMLHttpRequest")
      request.upload.onprogress = (event) => {
        watch()
        if (event.lengthComputable) this.show(row, "sending", `Uploading… ${Math.round((event.loaded / event.total) * 100)}%`, event.loaded / event.total)
      }
      // Sent; the server is now cleaning the photo (it can take a few seconds for a big one).
      request.upload.onload = () => { clearTimeout(this.stall); this.show(row, "sending", "Processing…", 1) }
      request.onload = done(() => this.answered(row, request))
      request.onerror = done(() => this.dropped(row, "The connection dropped."))
      request.onabort = done(() => this.dropped(row, row.stalled ? "The upload stalled." : "The upload stopped."))
      request.ontimeout = done(() => this.dropped(row, "The upload took too long."))
      request.timeout = 10 * 60_000

      row.stalled = false
      this.show(row, "sending", "Uploading…", 0)
      watch()
      request.send(body)
    })
  }

  answered(row, request) {
    const status = request.status
    const plain = (request.getResponseHeader("Content-Type") || "").startsWith("text/plain")
    if (status === 201) {
      this.countValue += 1
      this.listTarget.insertAdjacentHTML("beforeend", request.responseText)
      row.remove()
      this.say(`Photo ${this.countValue} added.`)
    } else if (status === 422 && plain) {
      this.failed(row, request.responseText, false) // the server refused this file; a retry won't change that
    } else if (status === 413) {
      this.failed(row, "This photo is too large to upload.", false)
    } else if (status === 401) {
      this.signedOut()
    } else if (status === 403 || status === 404) {
      this.failed(row, `You can't add photos to this ${this.nounValue} any more.`, false)
    } else if (status === 422) {
      this.failed(row, "This page is out of date. Reload it, then add the photo again.", false)
    } else {
      this.failed(row, "Couldn't upload this photo.", true)
    }
  }

  // A dropped connection: try again by itself once the phone is back online.
  dropped(row, message) {
    row.network = true
    this.failed(row, navigator.onLine === false ? `${message} It'll upload when you're back online.` : message, true)
  }

  // Every photo still to go would fail the same way, so stop and say what to do.
  signedOut() {
    this.state = PAUSED
    this.queueTarget.querySelectorAll("[data-state=waiting], [data-state=sending]").forEach((row) =>
      this.failed(row, "You've been signed out. Sign in again in another tab, then tap Retry.", true, { quiet: true }))
    this.say("You've been signed out. Your photos are still here; sign in again, then tap Retry.")
  }

  reconnected() {
    this.queueTarget.querySelectorAll("[data-state=failed]").forEach((row) => { if (row.network) this.requeue(row) })
    this.next()
  }

  retry(event) {
    const row = event.target.closest("[data-state]")
    if (!row.retryable) return row.remove()
    this.state = null
    this.requeue(row)
    this.next()
  }

  requeue(row) {
    row.network = false
    this.show(row, "waiting", "Waiting…", 0)
  }

  // Photos not uploaded yet would be lost by leaving.
  get pending() {
    return [...this.queueTarget.querySelectorAll("[data-state]")].some((row) => row.dataset.state !== "failed" || row.retryable)
  }

  guard(event) {
    if (!this.pending) return
    event.preventDefault()
    event.returnValue = ""
  }

  confirmLeave(event) {
    if (this.pending && !window.confirm("Some photos haven't uploaded yet. Leave this page and lose them?")) event.preventDefault()
  }

  failed(row, message, retryable, { quiet = false } = {}) {
    row.retryable = retryable
    const button = row.querySelector("button")
    button.textContent = retryable ? "Retry" : "Dismiss"
    button.setAttribute("aria-label", `${button.textContent} ${row.file.name}`)
    const text = message.replace(`${row.file.name} `, "")
    this.show(row, "failed", text, 0)
    if (!quiet) this.say(message.startsWith(row.file.name) ? message : `${row.file.name}: ${text}`)
  }

  row(file) {
    const row = document.createElement("li")
    row.file = file
    row.className = "rounded-control border border-line p-2 text-sm2"
    row.innerHTML = `<div class="flex items-center gap-2"><div class="min-w-0 flex-1"><span class="block truncate font-medium text-ink"></span>
      <span class="status block text-muted"></span></div>
      <button type="button" data-action="photo-upload#retry" hidden>Retry</button></div>
      <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-sunken" aria-hidden="true"><div class="bar h-full w-0 bg-brand"></div></div>`
    row.querySelector("span").textContent = file.name
    row.querySelector("button").classList.add(...this.retryClasses)
    this.show(row, "waiting", "Waiting…", 0)
    return row
  }

  show(row, state, text, fraction) {
    row.dataset.state = state
    row.querySelector(".status").textContent = text
    row.querySelector(".bar").style.width = `${Math.round(fraction * 100)}%`
    row.querySelector("button").hidden = state !== "failed"
  }

  // Screen readers hear when a photo is added or fails, not every percent.
  say(text) {
    this.announceTarget.textContent = ""
    requestAnimationFrame(() => { this.announceTarget.textContent = text })
  }
}
