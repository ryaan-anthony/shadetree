import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The quote builder (QTE-01). Lines are rows of the one form; their field names carry their
// position (quote[lines][3][name]) and are renumbered whenever rows change. The whole draft
// autosaves shortly after each change and again when the page is hidden (a phone locking or
// switching apps), with keepalive so the request survives the page going away. The server
// answers with a turbo stream: totals from the shared pricing code, line totals, errors and
// the new lock_version (also in an X-Lock-Version header, applied at once so a save queued
// behind this one isn't refused as stale). A save from a stale tab gets a conflict banner
// instead of overwriting newer work.
//
// Saves are sent URL-encoded (far smaller than multipart), and use keepalive only within the
// browser's 64 KiB keepalive limit; while there are unsaved changes, leaving the page asks
// first. Uploading a file submits the whole form as a normal request and pauses autosave.
// Browsers refuse keepalive bodies over 64 KiB; leave room for headers.
const KEEPALIVE_LIMIT = 60 * 1024

export default class extends Controller {
  static targets = ["line", "lines", "template", "empty", "status", "property"]
  static values = { propertyUrl: String, delay: { type: Number, default: 700 } }

  connect() {
    this.dirty = false
    this.saving = null
    this.onHide = () => { if (document.visibilityState === "hidden") this.flush() }
    this.onPageHide = () => this.flush()
    document.addEventListener("visibilitychange", this.onHide)
    window.addEventListener("pagehide", this.onPageHide)
    this.onBeforeVisit = (event) => { if (this.dirty) this.flush() }
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    this.onBeforeUnload = (event) => {
      if (!this.dirty && !this.saving) return
      this.flush()
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)
    this.element.addEventListener("submit", () => this.renumber())
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onHide)
    window.removeEventListener("pagehide", this.onPageHide)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    this.flush()
  }

  // Any edit in the form, except the file field (uploads submit the form themselves) and
  // the pickers' own search boxes, which aren't part of the quote.
  changed(event) {
    const target = event.target
    if (target.type === "file" || !target.name || target.closest("[data-controller~=catalog-picker]")) return
    this.schedule()
  }

  schedule() {
    if (this.uploading) return
    this.dirty = true
    this.setStatus("Unsaved changes")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  saveNow() {
    if (this.dirty) this.save()
  }

  addFromCatalog(event) {
    const item = event.detail
    this.addLine({
      catalog_item: item.uid, name: item.name, description: item.description || "", unit: item.unit || "",
      unit_price: item.unit_price || "", taxable: item.taxable !== false
    })
  }

  addCustom() {
    const row = this.addLine({})
    row.querySelector("[data-field=name]")?.focus()
  }

  addLine(values) {
    const key = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
    const html = this.templateTarget.innerHTML.replaceAll("NEW_KEY", key).replaceAll("NEW_INDEX", String(this.lineTargets.length))
    this.linesTarget.insertAdjacentHTML("beforeend", html)
    const row = this.lineTargets[this.lineTargets.length - 1]
    for (const [field, value] of Object.entries(values)) {
      const inputs = row.querySelectorAll(`[data-field=${field}]`)
      inputs.forEach((input) => {
        if (input.type === "checkbox") input.checked = !!value
        else if (input.type !== "hidden" || field !== "taxable") input.value = value
      })
    }
    if (values.description) row.querySelector("details")?.setAttribute("open", "")
    this.afterRowsChanged()
    return row
  }

  remove(event) {
    event.target.closest("[data-quote-builder-target=line]")?.remove()
    this.afterRowsChanged()
  }

  moveUp(event) {
    const row = event.target.closest("[data-quote-builder-target=line]")
    if (row?.previousElementSibling) row.parentNode.insertBefore(row, row.previousElementSibling)
    this.afterRowsChanged(event.target)
  }

  moveDown(event) {
    const row = event.target.closest("[data-quote-builder-target=line]")
    if (row?.nextElementSibling) row.parentNode.insertBefore(row.nextElementSibling, row)
    this.afterRowsChanged(event.target)
  }

  afterRowsChanged(focus) {
    this.renumber()
    this.emptyTarget.hidden = this.lineTargets.length > 0
    if (focus) focus.focus()
    this.schedule()
  }

  // quote[lines][N][field] in document order.
  renumber() {
    this.lineTargets.forEach((row, index) => {
      row.querySelectorAll("[data-field]").forEach((input) => {
        input.name = `quote[lines][${index}][${input.dataset.field}]`
      })
    })
  }

  // The client picker chose someone else: reload the property choices, then save (the
  // server also resets the property and, if exemption differs, the taxes).
  clientChanged(event) {
    const url = new URL(this.propertyUrlValue, window.location.origin)
    url.searchParams.set("client", event.detail.uid)
    this.propertyTarget.src = url.toString()
    this.schedule()
  }

  // A file was chosen: submit the whole form normally, so the upload and any pending edits
  // save together and the page reloads with the attachment listed.
  upload() {
    clearTimeout(this.timer)
    this.uploading = true
    this.dirty = false
    this.setStatus("Uploading…")
    this.renumber()
    const submit = () => {
      this.element.dataset.turbo = "false" // a full-page request, so the redirect shows the file
      this.element.submit()
    }
    this.saving ? this.saving.then(submit) : submit()
  }

  async save({ keepalive = false } = {}) {
    clearTimeout(this.timer)
    if (this.uploading) return
    if (this.saving) {
      this.again = true
      this.againKeepalive ||= keepalive
      return this.saving
    }
    this.renumber()
    const form = new FormData(this.element)
    form.delete("quote[attachments][]")
    form.delete("_method")
    const body = new URLSearchParams(form)
    const fits = new Blob([body.toString()]).size < KEEPALIVE_LIMIT
    this.dirty = false
    this.setStatus("Saving…")
    this.saving = fetch(this.element.action, {
      method: "PATCH",
      body,
      keepalive: keepalive && fits,
      credentials: "same-origin",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    }).then(async (response) => {
      // Apply the new lock_version now: the stream renders on the next frame, after a queued
      // save would already have read the old one.
      const lockVersion = response.headers.get("X-Lock-Version")
      const lockField = this.element.querySelector("#quote_lock_version")
      if (lockVersion && lockField) lockField.value = lockVersion
      const stream = await response.text()
      if (stream) Turbo.renderStreamMessage(stream)
      if (response.ok) this.setStatus(this.dirty ? "Unsaved changes" : "Saved")
      else if (response.status === 409) this.setStatus("Not saved")
      else { this.setStatus("Not saved: fix the errors above"); this.dirty = true }
    }).catch(() => {
      this.dirty = true
      this.setStatus("Offline: will retry")
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.save(), 5000)
    }).finally(() => {
      this.saving = null
      if (this.again) {
        const keepalive = this.againKeepalive
        this.again = this.againKeepalive = false
        this.save({ keepalive })
      }
    })
    return this.saving
  }

  // Leaving or hiding the page: save what's pending, with keepalive so it completes.
  flush() {
    if (this.dirty) this.save({ keepalive: true })
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
