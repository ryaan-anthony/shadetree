import { Controller } from "@hotwired/stimulus"

// ACC-08: the guided tour. One non-modal dialog steps through the stops, pointing at the element
// with data-tour="<target>" (the first of a stop's targets on the page). It takes focus at each
// stop and gives it back at the end, Escape ends it, and the page stays usable underneath: there
// is no backdrop and no focus trap. Below the desktop breakpoint it is a bottom sheet, and stops
// in the menu open the menu drawer.
//
// Anything with data-tour-start starts it. Where it is is kept for this tab (sessionStorage), so
// it resumes after a look at another page; first-time tips stay away while it runs. Each move is
// reported to the server for measurement, unless support is viewing as the member.
const NARROW = "(max-width: 959.98px)"
const GAP = 12

export default class extends Controller {
  static targets = ["dialog", "count", "title", "text", "link", "back", "next"]
  static values = { tour: Object, url: String, record: Boolean, scope: String, autostart: Boolean, count: String, next: String, done: String }

  connect() {
    this.startClick = (event) => {
      const button = event.target.closest("[data-tour-start]")
      if (!button) return
      event.preventDefault()
      this.start(button)
    }
    this.reposition = () => { if (this.current) this.place() }
    this.beforeCache = () => this.hide()
    document.addEventListener("click", this.startClick)
    window.addEventListener("resize", this.reposition)
    document.addEventListener("scroll", this.reposition, { passive: true, capture: true })
    document.addEventListener("turbo:before-cache", this.beforeCache)

    if (this.autostartValue) {
      const url = new URL(window.location.href)
      url.searchParams.delete("tour")
      history.replaceState(history.state, "", url)
      this.start()
    } else if (this.saved !== null && this.stops[this.saved]) {
      this.show(this.saved, { quietly: true })
    }
  }

  disconnect() {
    document.removeEventListener("click", this.startClick)
    window.removeEventListener("resize", this.reposition)
    document.removeEventListener("scroll", this.reposition, { capture: true })
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.hide()
  }

  get stops() { return this.tourValue.stops || [] }
  get storageKey() { return `shadetree:tour:${this.scopeValue}` }

  get saved() {
    try {
      const value = sessionStorage.getItem(this.storageKey)
      return value === null ? null : Number(value)
    } catch { return null }
  }

  set saved(index) {
    try {
      index === null ? sessionStorage.removeItem(this.storageKey) : sessionStorage.setItem(this.storageKey, String(index))
    } catch { /* private mode: the tour just won't resume */ }
  }

  start(opener = document.activeElement) {
    if (!this.stops.length) return
    this.opener = opener
    document.querySelectorAll("[data-tour-offer]").forEach((offer) => { offer.hidden = true })
    this.record("start", this.stops[0].key)
    this.show(0, { quietly: true })
  }

  next() {
    if (this.index >= this.stops.length - 1) return this.finish()
    this.show(this.index + 1)
  }

  back() {
    if (this.index > 0) this.show(this.index - 1)
  }

  end() {
    this.record("end", this.stops[this.index].key)
    this.close()
  }

  finish() {
    this.record("finish", this.stops[this.index].key)
    this.close(this.tourValue.next_step)
  }

  keydown(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    event.stopPropagation()
    this.end()
  }

  show(index, { quietly = false } = {}) {
    const stop = this.stops[index]
    const last = index === this.stops.length - 1
    this.index = index
    this.saved = index
    if (!quietly) this.record("step", stop.key)

    this.countTarget.textContent = this.countValue.replace("%{at}", index + 1).replace("%{of}", this.stops.length)
    this.titleTarget.textContent = stop.title
    this.textTarget.textContent = stop.text
    this.linkTarget.hidden = !stop.link
    if (stop.link) {
      this.linkTarget.textContent = stop.link.label
      this.linkTarget.href = stop.link.href
    }
    this.backTarget.hidden = index === 0
    this.nextTarget.textContent = last ? (this.tourValue.next_step?.label || this.doneValue) : this.nextValue

    this.unmark()
    this.current = this.findTarget(stop)
    this.current?.classList.add("tour-target")
    this.dialogTarget.hidden = false
    document.documentElement.classList.add("tour-open")
    this.useDrawer(this.current?.closest("#app-sidebar"))
    this.place()
    this.current?.scrollIntoView({ block: "nearest", behavior: this.motion })
    this.dialogTarget.focus({ preventScroll: true })
  }

  // The first of the stop's targets on the page. Menu links count while the drawer is closed.
  findTarget(stop) {
    for (const name of stop.targets) {
      const element = document.querySelector(`[data-tour~="${name}"]`)
      if (element && (element.closest("#app-sidebar") || element.getClientRects().length)) return element
    }
    return null
  }

  place() {
    const dialog = this.dialogTarget
    const narrow = window.matchMedia(NARROW).matches
    dialog.classList.toggle("tour-sheet", narrow)
    if (narrow) {
      dialog.style.left = dialog.style.top = ""
      // Room under the menu, so a link near its foot isn't hidden by the sheet.
      document.documentElement.style.setProperty("--tour-sheet-height", `${dialog.offsetHeight}px`)
      return
    }

    const box = dialog.getBoundingClientRect()
    const vw = document.documentElement.clientWidth
    const vh = window.innerHeight
    const clamp = (value, max) => Math.max(GAP, Math.min(value, max - GAP))
    let left = vw - box.width - 24
    let top = vh - box.height - 24 // no target on the page: the corner
    if (this.current) {
      const rect = this.current.getBoundingClientRect()
      const fits = { right: rect.right + GAP + box.width <= vw - GAP, below: rect.bottom + GAP + box.height <= vh - GAP, above: rect.top - GAP - box.height >= GAP }
      if (fits.right && (this.current.closest("#app-sidebar") || !(fits.below || fits.above))) {
        left = rect.right + GAP
        top = rect.top
      } else if (fits.below || fits.above) {
        left = rect.left
        top = fits.below ? rect.bottom + GAP : rect.top - GAP - box.height
      }
    }
    dialog.style.left = `${clamp(left, vw - box.width)}px`
    dialog.style.top = `${clamp(top, vh - box.height)}px`
  }

  useDrawer(inMenu) {
    if (!window.matchMedia(NARROW).matches) return
    const element = document.querySelector("[data-controller~=drawer]")
    const drawer = element && this.application.getControllerForElementAndIdentifier(element, "drawer")
    if (!drawer) return
    if (inMenu && drawer.panelTarget.dataset.open !== "true") drawer.open()
    if (!inMenu) drawer.close()
  }

  // Closes the tour; focus goes to the checklist step it leads to, else back where it started.
  close(nextStep = null) {
    this.saved = null
    this.hide()
    this.useDrawer(false)
    const step = nextStep && document.getElementById(nextStep.id)?.querySelector("a, button")
    const opener = this.opener !== document.body && this.opener?.isConnected && this.opener.getClientRects().length ? this.opener : null
    const fallback = document.querySelector("#main h1")
    if (fallback && !step && !opener) fallback.setAttribute("tabindex", "-1")
    const focus = step || opener || fallback
    focus?.focus({ preventScroll: true })
    focus?.scrollIntoView({ block: "nearest", behavior: this.motion })
  }

  hide() {
    if (!this.hasDialogTarget) return
    this.dialogTarget.hidden = true
    document.documentElement.classList.remove("tour-open")
    this.unmark()
  }

  unmark() {
    this.current?.classList.remove("tour-target")
    this.current = null
  }

  get motion() { return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" }

  record(event, stop) {
    if (!this.recordValue) return
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify({ event, stop }),
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }
}
