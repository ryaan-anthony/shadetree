import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// JOB-03: drag a visit on the calendar to another day, time or person (mouse only; phones and
// keyboards open the visit, with Enter or Space, and use "Move" in its details, QA #274). Times snap to 15 minutes. Warnings (hours,
// closures, someone already booked) are asked about first; after a move the calendar reloads
// and its toast offers Undo.
const SNAP_MINUTES = 15
const THRESHOLD_PX = 5

export default class extends Controller {
  static targets = ["visit", "column", "status"]
  static values = { url: String, firstHour: Number, hourPx: Number, context: Object }

  connect() {
    this.restoreScroll()
  }

  disconnect() {
    this.cancel()
  }

  // A link is natively draggable; the browser's own link drag would cancel ours.
  visitTargetConnected(element) {
    element.draggable = false
    element.addEventListener("pointerdown", this.press)
    element.addEventListener("dragstart", this.noNativeDrag)
  }

  visitTargetDisconnected(element) {
    element.removeEventListener("pointerdown", this.press)
    element.removeEventListener("dragstart", this.noNativeDrag)
  }

  noNativeDrag = (event) => event.preventDefault()

  press = (event) => {
    if (event.button !== 0 || event.pointerType !== "mouse" || this.drag) return
    event.preventDefault() // no text selection while dragging; the click still opens the visit
    const element = event.currentTarget
    const box = element.getBoundingClientRect()
    this.drag = { element, x: event.clientX, y: event.clientY, grabY: event.clientY - box.top, moving: false }
    window.addEventListener("pointermove", this.move)
    window.addEventListener("pointerup", this.release)
    window.addEventListener("keydown", this.escape)
  }

  move = (event) => {
    const drag = this.drag
    if (!drag) return
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y
    if (!drag.moving) {
      if (Math.hypot(dx, dy) < THRESHOLD_PX) return
      drag.moving = true
      drag.element.classList.add("cal-dragging")
      drag.badge = Object.assign(document.createElement("span"), { className: "absolute right-1 top-0.5 rounded bg-ink px-1 text-xs text-white" })
      drag.element.append(drag.badge)
    }
    event.preventDefault()
    drag.element.style.translate = `${dx}px ${dy}px`
    drag.target = this.dropAt(event)
    this.columnTargets.forEach((column) => column.classList.toggle("cal-drop", column === drag.target?.column))
    drag.badge.textContent = drag.target ? (drag.target.at ? this.label(drag.target.at) : "Anytime") : "—"
  }

  release = (event) => {
    const drag = this.drag
    if (!drag) return
    this.stopListening()
    if (!drag.moving) { this.drag = null; return } // a click: opens the visit as usual
    // The click that ends a drag mustn't also open the visit. It lands wherever the pointer is
    // (the dragged visit ignores the pointer), so catch it on the window, for this click only.
    const swallow = (click) => { click.preventDefault(); click.stopImmediatePropagation() }
    window.addEventListener("click", swallow, { capture: true, once: true })
    setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0)
    const target = this.dropAt(event)
    this.reset()
    if (!target || this.unchanged(drag.element, target)) return
    this.send(drag.element, target)
  }

  escape = (event) => {
    if (event.key === "Escape") this.cancel()
  }

  cancel() {
    if (!this.drag) return
    this.stopListening()
    this.reset()
  }

  stopListening() {
    window.removeEventListener("pointermove", this.move)
    window.removeEventListener("pointerup", this.release)
    window.removeEventListener("keydown", this.escape)
  }

  reset() {
    const drag = this.drag
    this.drag = null
    if (!drag) return
    drag.element.classList.remove("cal-dragging")
    drag.element.style.translate = ""
    drag.badge?.remove()
    this.columnTargets.forEach((column) => column.classList.remove("cal-drop"))
  }

  // The column under the pointer, if this visit can go there, and the time it would start.
  dropAt(event) {
    const element = this.drag.element
    const column = document.elementFromPoint(event.clientX, event.clientY)?.closest("[data-schedule-drag-target=column]")
    if (!column || !this.element.contains(column)) return null
    const anytime = element.dataset.timing === "anytime"
    if ((column.dataset.kind === "anytime") !== anytime) return null // a timed visit keeps a time, an anytime one doesn't get one
    if (anytime) return { column }

    const top = event.clientY - this.drag.grabY - column.getBoundingClientRect().top
    const minutes = this.firstHourValue * 60 + Math.round((top / this.hourPxValue) * 60 / SNAP_MINUTES) * SNAP_MINUTES
    const clamped = Math.min(Math.max(minutes, 0), 24 * 60 - SNAP_MINUTES)
    return { column, at: `${String(Math.floor(clamped / 60)).padStart(2, "0")}:${String(clamped % 60).padStart(2, "0")}` }
  }

  unchanged(element, { column, at }) {
    const sameColumn = element.closest("[data-schedule-drag-target=column]") === column
    return sameColumn && (!at || at === element.dataset.start)
  }

  async send(element, { column, at }, confirm) {
    const body = { ...this.contextValue, on: column.dataset.date, lock_version: element.dataset.lock }
    if (at) body.at = at
    if (column.dataset.member !== undefined && column.dataset.member !== element.dataset.member) {
      body.from = element.dataset.member
      body.to = column.dataset.member
    }
    if (confirm) body.confirm = confirm
    element.classList.add("cal-moving")
    this.say(`Moving ${element.dataset.label}…`)

    let response
    try {
      response = await fetch(this.urlValue.replace("ID", element.dataset.visit), {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify(body)
      })
    } catch {
      element.classList.remove("cal-moving")
      this.say("The connection dropped. Nothing was moved.")
      return
    }
    const answer = await response.json().catch(() => ({}))
    if (response.status === 422 && answer.warnings) {
      if (await this.ask(answer.warnings)) return this.send(element, { column, at }, answer.confirm)
      element.classList.remove("cal-moving")
      this.say("Not moved.")
      return
    }
    try { sessionStorage.setItem("schedule-focus", element.dataset.visit) } catch {} // focus comes back to it (schedule_focus_controller)
    this.reload() // moved (the toast offers Undo), or refused (the toast says why)
  }

  // The warnings, in the page's confirm dialog: "Move anyway" goes ahead.
  ask(warnings) {
    const dialog = document.getElementById("confirm-dialog")
    if (!dialog) return Promise.resolve(window.confirm(`${warnings.join("\n")}\n\nMove anyway?`))

    dialog.querySelector("[data-confirm-title]").textContent = "Before you move this"
    const list = document.createElement("ul")
    list.className = "list-disc space-y-1 pl-5"
    warnings.forEach((warning) => list.append(Object.assign(document.createElement("li"), { textContent: warning })))
    dialog.querySelector("[data-confirm-message]").replaceChildren(list)
    const button = dialog.querySelector("[data-confirm-button]")
    const style = button.className
    button.textContent = "Move anyway"
    button.className = style.replace("btn-danger-solid", "btn-primary") // a warning, not something destructive
    dialog.showModal()
    return new Promise((resolve) => {
      dialog.addEventListener("close", () => {
        dialog.querySelector("[data-confirm-title]").textContent = "Are you sure?"
        button.className = style
        resolve(dialog.returnValue === "confirm")
      }, { once: true })
    })
  }

  // Reload in place, keeping where the grid was scrolled to.
  reload() {
    const scroller = this.element.querySelector(".overflow-y-auto")
    try { sessionStorage.setItem("schedule-scroll", JSON.stringify({ grid: scroller?.scrollTop || 0, page: window.scrollY })) } catch {}
    Turbo.visit(window.location.href, { action: "replace" })
  }

  restoreScroll() {
    let saved = null
    try {
      saved = JSON.parse(sessionStorage.getItem("schedule-scroll"))
      sessionStorage.removeItem("schedule-scroll")
    } catch {}
    if (!saved) return
    const scroller = this.element.querySelector(".overflow-y-auto")
    if (scroller) scroller.scrollTop = saved.grid
    requestAnimationFrame(() => window.scrollTo(0, saved.page))
  }

  label(clock) {
    const [hour, minute] = clock.split(":").map(Number)
    return `${hour % 12 || 12}${minute ? `:${String(minute).padStart(2, "0")}` : ""} ${hour < 12 ? "am" : "pm"}`
  }

  say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
