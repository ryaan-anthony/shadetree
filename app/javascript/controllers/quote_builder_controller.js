import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The document builder: quotes (QTE-01) and invoices (PAY-01, scope "invoice"). Lines are rows
// of the one form; their field names carry their position (quote[lines][3][name]) and are
// renumbered whenever rows change. The whole draft
// autosaves shortly after each change and again when the page is hidden (a phone locking or
// switching apps), with keepalive so the request survives the page going away. The server
// answers with a turbo stream: totals from the shared pricing code, line totals, errors and
// the new lock_version (also in an X-Lock-Version header, applied at once so a save queued
// behind this one isn't refused as stale). A save from a stale tab gets a conflict banner
// instead of overwriting newer work.
//
// Saves are sent URL-encoded (far smaller than multipart), with keepalive whenever they fit
// the browser's 64 KiB keepalive limit; while there are unsaved changes, leaving the page asks
// first. "Save draft" and "Preview as client" go through the same one-at-a-time queue.
// Uploading a file submits the whole form as a normal request and pauses autosave.
// Browsers refuse keepalive bodies over 64 KiB; leave room for headers.
const KEEPALIVE_LIMIT = 60 * 1024

export default class extends Controller {
  static targets = ["form", "line", "lines", "template", "empty", "status", "property"]
  static values = { propertyUrl: String, delay: { type: Number, default: 700 }, scope: { type: String, default: "quote" } }

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
      if (this.uploading || (!this.dirty && !this.saving && !this.photosTicked())) return
      this.flush()
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onHide)
    window.removeEventListener("pagehide", this.onPageHide)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    this.flush()
  }

  // Any edit in the form, except the file field and the invoice's job-photo ticks (both are
  // added by submitting the form, see upload) and the pickers' own search boxes, which aren't
  // part of the document.
  changed(event) {
    const target = event.target
    if (target.name?.endsWith("[job_photos][]")) return this.photoTicked()
    if (target.type === "file" || !target.name || target.closest("[data-controller~=catalog-picker]")) return
    this.schedule()
  }

  // Ticked job photos are added by the "Add ticked photos" button or by "Save draft"; until
  // then the button is live, the status says so and leaving the page asks first.
  photoTicked() {
    const ticked = this.photosTicked()
    this.element.querySelectorAll("[data-photos-add]").forEach((button) => { button.disabled = !ticked })
    if (ticked) this.setStatus("Ticked photos aren't added yet")
    else if (!this.dirty && !this.saving) this.setStatus("Saved")
  }

  photosTicked() {
    return this.formTarget.querySelector(`input[name="${this.scopeValue}[job_photos][]"]:checked`) !== null
  }

  schedule() {
    if (this.uploading) return
    this.dirty = true
    this.setStatus("Unsaved changes")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  // "Save draft" goes through the same queue as autosave, so it can't race one in flight. With
  // job photos ticked it adds them too (a normal submit, as an upload is).
  submit(event) {
    event.preventDefault()
    this.photosTicked() ? this.upload() : this.save()
  }

  // Send: save first, then go to the send page in this tab.
  async saveAndGo(event) {
    event.preventDefault()
    const href = event.currentTarget.href // currentTarget is gone after the await
    if (this.dirty) this.save()
    await this.saving
    // Only once everything is saved: after a conflict (another tab saved newer work) the
    // page says so and the quote stays here, so an older version can't go out.
    if (!this.dirty && !this.conflict) Turbo.visit(href)
  }

  // CAT-08: a button for a form outside the builder (re-pricing): save first, then submit that
  // form with the latest lock_version, so nothing pending is lost and a stale tab is refused.
  async saveAndSubmit(event) {
    event.preventDefault()
    const button = event.currentTarget
    const form = button.form
    if (this.dirty) this.save()
    await this.saving
    if (this.dirty || this.conflict || !form) return
    const lock = this.formTarget.querySelector(`#${this.scopeValue}_lock_version`)
    if (lock && form.elements.lock_version) form.elements.lock_version.value = lock.value
    form.requestSubmit(button)
  }

  // Download PDF: save first, so the PDF has the latest.
  async download(event) {
    event.preventDefault()
    const href = event.currentTarget.href
    if (this.dirty) this.save()
    await this.saving
    window.location = href
  }

  // The invoice's payment terms (PAY-01): a custom date shows the date box; other terms show
  // the date they give (filled in by the next autosave). The disabled box isn't submitted.
  termsChanged(event) {
    const custom = event.target.value === "custom"
    const box = this.element.querySelector("[data-due-custom]")
    const fixed = this.element.querySelector("[data-due-fixed]")
    if (!box || !fixed) return
    box.hidden = !custom
    fixed.hidden = custom
    box.querySelector("input").disabled = !custom
    if (!custom) fixed.querySelector("#invoice_due_text").textContent = "…"
  }

  // Preview as client: save first, so the preview shows the latest. The tab opens at once
  // (popup blockers allow that only during the click) and is pointed at the preview after.
  async preview(event) {
    event.preventDefault()
    const href = event.currentTarget.href // currentTarget is gone after the await
    const tab = window.open("about:blank", "_blank")
    if (tab) tab.opener = null
    if (this.dirty) this.save()
    await this.saving
    if (tab) tab.location = href
    else window.location = href
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
        input.name = `${this.scopeValue}[lines][${index}][${input.dataset.field}]`
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

  // A file was chosen (or ticked photos added): submit the whole form normally, so the upload and any pending edits
  // save together and the page reloads with the attachment listed.
  upload() {
    clearTimeout(this.timer)
    this.uploading = true
    this.dirty = false
    this.setStatus("Uploading…")
    this.renumber()
    const submit = () => {
      this.formTarget.dataset.turbo = "false" // a full-page request, so the redirect shows the file
      this.formTarget.submit()
    }
    this.saving ? this.saving.then(submit) : submit()
  }

  async save() {
    clearTimeout(this.timer)
    if (this.uploading) return
    if (this.saving) {
      this.again = true
      return this.saving
    }
    this.renumber()
    const formElement = this.formTarget
    const form = new FormData(formElement)
    form.delete(`${this.scopeValue}[attachments][]`)
    form.delete(`${this.scopeValue}[job_photos][]`)
    form.delete("_method")
    const body = new URLSearchParams(form)
    const fits = new Blob([body.toString()]).size < KEEPALIVE_LIMIT
    this.dirty = false
    this.setStatus("Saving…")
    // keepalive whenever it fits, so a save in flight survives the page being closed or killed.
    this.saving = fetch(formElement.action, {
      method: "PATCH",
      body,
      keepalive: fits,
      credentials: "same-origin",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    }).then(async (response) => {
      // Apply the new lock_version now: the stream renders on the next frame, after a queued
      // save would already have read the old one.
      const lockVersion = response.headers.get("X-Lock-Version")
      const lockField = formElement.querySelector(`#${this.scopeValue}_lock_version`)
      if (lockVersion && lockField) lockField.value = lockVersion
      const stream = await response.text()
      // The builder may have been left meanwhile (another quote has the same target ids).
      if (!formElement.isConnected) return
      if (stream) Turbo.renderStreamMessage(stream)
      this.conflict = response.status === 409
      if (response.ok) this.setStatus(this.dirty ? "Unsaved changes" : "Saved")
      else if (this.conflict) this.setStatus("Not saved")
      else { this.setStatus("Not saved: fix the errors above"); this.dirty = true }
    }).catch(() => {
      this.dirty = true
      this.setStatus("Offline: will retry")
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.save(), 5000)
    }).finally(() => {
      this.saving = null
      if (this.again) {
        this.again = false
        // Returned, so anyone awaiting this save (Preview) also waits for the queued one.
        return this.save()
      }
    })
    return this.saving
  }

  // Leaving or hiding the page: save what's pending now (with keepalive, like every save).
  flush() {
    if (this.dirty) this.save()
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
