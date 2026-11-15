import { Controller } from "@hotwired/stimulus"

// Fills a hidden field with the browser's time zone (e.g. "America/Chicago") so a new business
// starts in the right zone. The server ignores values it doesn't recognise.
export default class extends Controller {
  static targets = ["field"]

  connect() {
    if (this.fieldTarget.value) return
    try {
      this.fieldTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone || ""
    } catch {
      // Older browsers: leave blank, the owner can set it in settings.
    }
  }
}
