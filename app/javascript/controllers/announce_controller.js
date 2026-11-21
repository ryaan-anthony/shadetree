import { Controller } from "@hotwired/stimulus"

// Reads a status message out to screen readers, through the page's polite live region
// (#announcer, kept across Turbo visits). A live region that arrives already holding its text,
// as a toast does after a Turbo visit, isn't announced; a change to one already there is.
// Messages that arrive together are read as one; the region empties a few seconds later, so a
// screen reader browsing the page doesn't meet old news. Turbo's cached preview of a page (on
// Back) announces nothing, and toasts aren't cached (data-turbo-temporary) in the first place.
//
//   <div data-controller="announce" data-turbo-temporary><span data-announce-target="text">Saved.</span></div>
const SETTLE = 150
const CLEAR_AFTER = 5000
let pending = []
let flushTimer
let clearTimer

function flush() {
  const announcer = document.getElementById("announcer")
  const text = pending.join(" ")
  pending = []
  if (!announcer || !text) return

  clearTimeout(clearTimer)
  announcer.textContent = ""
  // A moment between emptying and filling, so the change is noticed as new.
  setTimeout(() => {
    announcer.textContent = text
    clearTimer = setTimeout(() => { if (announcer.textContent === text) announcer.textContent = "" }, CLEAR_AFTER)
  }, 50)
}

export default class extends Controller {
  static targets = ["text"]

  connect() {
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    const text = (this.hasTextTarget ? this.textTarget : this.element).textContent.trim()
    if (!text) return

    pending.push(text)
    // Spoken a moment later: during a Turbo render the kept announcer is swapped in after the
    // new page's controllers connect, and a just-loaded page's region needs a moment to register.
    clearTimeout(flushTimer)
    flushTimer = setTimeout(flush, SETTLE)
  }
}
