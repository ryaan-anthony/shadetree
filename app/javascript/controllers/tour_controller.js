import { Controller } from "@hotwired/stimulus"

// ACC-08: the guided tour. One non-modal dialog steps through the stops, pointing at the element
// with data-tour="<target>" (the first of a stop's targets on the page) and saying what it points
// at for screen readers. It takes focus at each stop and gives it back at the end; F6 moves focus
// between it and what it points at; Escape ends it (unless a menu or modal is open). There is no
// backdrop and no focus trap. Below the desktop breakpoint it is a bottom sheet that the page and
// the target scroll clear of, and stops in the menu open the menu drawer.
//
// Anything with data-tour-start starts it. Leaving the page ends it where it was, except through
// the tour's own sample-quote link: then its place is kept for this tab (sessionStorage, keyed by
// business and member, for 30 minutes) and it resumes on return. A reload isn't leaving (owner,
// 2026-11-24): the page can't tell a reload from leaving as it unloads, so it reports the end and
// notes its place; if this tab's next page is a fresh load of the same page within a minute, not
// by Back or Forward, the tour carries on there and the server is told it resumed. Moves are
// reported to the server in order, for measurement, unless support is viewing as the member.
const NARROW = "(max-width: 959.98px)"
const GAP = 12
const KEEP_FOR = 30 * 60 * 1000
const AGAIN_WITHIN = 60 * 1000

// A place noted as a page unloaded is only for that page loaded again, by this tab's next page
// load: any other page drops it, and so does a Turbo visit.
const dropLeft = (keep = () => false) => {
  try {
    Object.keys(sessionStorage).filter((key) => key.startsWith("shadetree:tour:")).forEach((key) => {
      const kept = JSON.parse(sessionStorage.getItem(key) || "null")
      if (kept?.left && !keep(kept)) sessionStorage.removeItem(key)
    })
  } catch { /* nothing kept */ }
}
const here = () => window.location.href.split("#")[0]
dropLeft((kept) => kept.url === here())
document.addEventListener("turbo:visit", () => dropLeft())

export default class extends Controller {
  static targets = ["dialog", "count", "title", "text", "link", "back", "next", "pointing"]
  static values = {
    tour: Object, url: String, record: Boolean, scope: String, autostart: Boolean,
    count: String, next: String, done: String, pointing: String, inMenu: String, missing: String
  }

  connect() {
    this.queue = Promise.resolve()
    this.startClick = (event) => {
      const button = event.target.closest("[data-tour-start]")
      if (!button) return
      event.preventDefault()
      this.start(button)
    }
    this.keys = (event) => this.keydown(event)
    this.reposition = () => { if (this.running) this.place() }
    this.beforeCache = () => this.hide()
    this.pagehide = () => this.leave({ unloading: true })
    // Back to this page from the back/forward cache: from the sample quote the tour carries on;
    // otherwise it was left, so it stays ended.
    this.pageshow = (event) => {
      if (!event.persisted) return
      if (this.keeping) this.keeping = false
      else if (!this.running) this.hide()
      this.takeKept()
    }
    document.addEventListener("click", this.startClick)
    document.addEventListener("keydown", this.keys, { capture: true })
    window.addEventListener("resize", this.reposition)
    document.addEventListener("scroll", this.reposition, { passive: true, capture: true })
    document.addEventListener("turbo:before-cache", this.beforeCache)
    window.addEventListener("pagehide", this.pagehide)
    window.addEventListener("pageshow", this.pageshow)

    // After a Turbo visit finishes rendering (it scrolls to the top, which would undo ours).
    const kept = this.takeKept()
    const later = (fn) => requestAnimationFrame(() => requestAnimationFrame(() => { if (this.element.isConnected) fn() }))
    if (this.autostartValue) {
      const url = new URL(window.location.href)
      url.searchParams.delete("tour")
      history.replaceState(history.state, "", url)
      later(() => this.start())
    } else if (kept && this.stops[kept.index]) {
      later(() => {
        if (kept.reloaded) this.record("resume", this.stops[kept.index].key)
        this.show(kept.index, { quietly: true })
      })
    }
  }

  disconnect() {
    this.leave()
    document.removeEventListener("click", this.startClick)
    document.removeEventListener("keydown", this.keys, { capture: true })
    window.removeEventListener("resize", this.reposition)
    document.removeEventListener("scroll", this.reposition, { capture: true })
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    window.removeEventListener("pagehide", this.pagehide)
    window.removeEventListener("pageshow", this.pageshow)
    this.hide()
  }

  get stops() { return this.tourValue.stops || [] }
  get running() { return this.index !== undefined && this.index !== null }
  get storageKey() { return `shadetree:tour:${this.scopeValue}` }

  // The place kept by the sample-quote link, if it's recent, or by unloading this page, if this
  // is that page loaded again ({ index, reloaded }); read once.
  takeKept() {
    try {
      const kept = JSON.parse(sessionStorage.getItem(this.storageKey) || "null")
      sessionStorage.removeItem(this.storageKey)
      if (!kept) return null
      if (kept.left) return this.loadedAgain(kept) ? { index: kept.index, reloaded: true } : null
      return Date.now() - kept.at < KEEP_FOR ? { index: kept.index } : null
    } catch { return null }
  }

  // This document is a fresh load of the page the tour was on, soon after it unloaded: a reload,
  // or loading the same address again. Not Back or Forward, or a later return.
  loadedAgain(kept) {
    const how = performance.getEntriesByType?.("navigation")?.[0]?.type
    return how !== "back_forward" && kept.url === here() && Date.now() - kept.at < AGAIN_WITHIN
  }

  // The tour's own link: keep its place so it resumes on return.
  keep() {
    this.keeping = true
    this.save({ index: this.index, at: Date.now() })
  }

  save(place) {
    try { sessionStorage.setItem(this.storageKey, JSON.stringify(place)) } catch { /* it just won't resume */ }
  }

  // Leaving the page any other way (a highlighted menu link, the back button, closing the tab)
  // ends the tour where it was: recorded as ended at that stop. As the page unloads its place is
  // noted too, in case this is a reload.
  leave({ unloading = false } = {}) {
    if (!this.running || this.keeping) return
    this.record("end", this.stops[this.index].key)
    if (unloading) this.save({ index: this.index, at: Date.now(), url: here(), left: true })
    this.index = null
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
    if (!this.running || event.defaultPrevented) return
    if (event.key === "F6") {
      event.preventDefault()
      this.toggleFocus()
    } else if (event.key === "Escape" && !document.querySelector(".menu:not([hidden]), dialog[open]")) {
      event.preventDefault()
      event.stopPropagation()
      this.end()
    }
  }

  // F6: from the tour to what it points at, and back. In a container (the checklist) that's its
  // first link, else its first button; never a control marked data-tour-skip (like Hide, which
  // would do something mid-tour), else the container itself.
  toggleFocus() {
    if (!this.dialogTarget.contains(document.activeElement)) return this.dialogTarget.focus({ preventScroll: true })
    const target = this.current
    if (!target) return
    const focusable = target.matches("a[href], button") ? target : this.firstControl(target)
    if (focusable) return focusable.focus()
    target.setAttribute("tabindex", "-1")
    target.focus()
  }

  firstControl(container) {
    return container.querySelector("a[href]:not([data-tour-skip])") || container.querySelector("button:not([data-tour-skip]):not([disabled])")
  }

  show(index, { quietly = false } = {}) {
    const stop = this.stops[index]
    const last = index === this.stops.length - 1
    this.index = index
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
    this.pointingTarget.textContent = this.describe(this.current)
    this.dialogTarget.hidden = false
    this.dialogTarget.scrollTop = 0 // a short screen's sheet scrolls: each stop starts at its title
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

  // "Pointing at: Requests, in the menu", from the target's label, heading or text.
  describe(element) {
    if (!element) return this.missingValue
    const name = (element.getAttribute("aria-label") || element.querySelector("h2, h3")?.textContent ||
                  element.querySelector("span")?.textContent || element.textContent).trim()
    return this.pointingValue.replace("%{name}", name) + (element.closest("#app-sidebar") ? this.inMenuValue : "")
  }

  place() {
    const dialog = this.dialogTarget
    const narrow = window.matchMedia(NARROW).matches
    dialog.classList.toggle("tour-sheet", narrow)
    // The page, and the target, scroll clear of the sheet (WCAG 2.4.11).
    document.documentElement.style.setProperty("--tour-sheet-height", narrow ? `${dialog.offsetHeight}px` : "0px")
    if (narrow) {
      dialog.style.left = dialog.style.top = ""
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
      // To the right where it fits (clear of the page's heading), else below or above.
      if (rect.right + GAP + box.width <= vw - GAP) {
        left = rect.right + GAP
        top = rect.top
      } else if (rect.bottom + GAP + box.height <= vh - GAP || rect.top - GAP - box.height >= GAP) {
        left = rect.left
        top = rect.bottom + GAP + box.height <= vh - GAP ? rect.bottom + GAP : rect.top - GAP - box.height
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
    this.index = null
    this.hide()
    this.useDrawer(false)
    const stepElement = nextStep && document.getElementById(nextStep.id)
    const step = stepElement && this.firstControl(stepElement)
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
    document.documentElement.style.removeProperty("--tour-sheet-height")
    this.unmark()
  }

  unmark() {
    this.current?.classList.remove("tour-target")
    this.current = null
  }

  get motion() { return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" }

  // One at a time, in order: a quick click after the start mustn't land before it.
  record(event, stop) {
    if (!this.recordValue) return
    const body = JSON.stringify({ event, stop })
    this.queue = this.queue.then(() => fetch(this.urlValue, {
      method: "PATCH",
      headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body,
      credentials: "same-origin",
      keepalive: true
    })).catch(() => {})
  }
}
