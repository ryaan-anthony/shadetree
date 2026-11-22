import { Controller } from "@hotwired/stimulus"

// ACC-08: signing out forgets any guided tour kept in this tab (tour_controller.js).
export default class extends Controller {
  clear() {
    try {
      Object.keys(sessionStorage).filter((key) => key.startsWith("shadetree:tour:")).forEach((key) => sessionStorage.removeItem(key))
    } catch { /* nothing kept */ }
  }
}
