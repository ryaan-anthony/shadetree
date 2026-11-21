import { Controller } from "@hotwired/stimulus"

// Reads a status message out to screen readers, through the page's polite live region
// (#announcer, kept across Turbo visits). A live region that arrives already holding its text,
// as a toast does after a Turbo visit, isn't announced; a change to one already there is.
//
//   <div role="status" data-controller="announce"><span data-announce-target="text">Saved.</span></div>
export default class extends Controller {
  static targets = ["text"]

  connect() {
    const text = (this.hasTextTarget ? this.textTarget : this.element).textContent.trim()
    // Looked up when it's time to speak: during a Turbo render the kept announcer is swapped in
    // after the new page's controllers connect. The wait also lets a just-loaded page's region
    // register before its text changes.
    this.timer = setTimeout(() => {
      const announcer = document.getElementById("announcer")
      if (!announcer) return
      announcer.textContent = ""
      this.timer = setTimeout(() => { announcer.textContent = text }, 50)
    }, 150)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
