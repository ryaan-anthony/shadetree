import { Controller } from "@hotwired/stimulus"

// Rough, friendly strength guidance for new passwords. Length matters most; the server
// enforces the minimum.
export default class extends Controller {
  static targets = ["input", "bar", "label"]

  connect() {
    this.update()
  }

  update() {
    const value = this.inputTarget.value
    const min = Number(this.inputTarget.getAttribute("minlength") || 10)
    const score = this.score(value, min)
    const labels = ["", "Too short", "OK", "Good", "Strong"]
    const colors = ["", "bg-danger", "bg-warning", "bg-canopy-600", "bg-canopy"]

    this.barTargets.forEach((bar, index) => {
      bar.className = `flex-1 rounded-full ${index < score ? colors[score] : "bg-line"}`
    })
    this.labelTarget.textContent = labels[score]
  }

  score(value, min) {
    if (value.length === 0) return 0
    if (value.length < min) return 1
    const kinds = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((re) => re.test(value)).length
    const unique = new Set(value).size
    if (unique < 5) return 2
    if (value.length >= min + 6 || (value.length >= min + 2 && kinds >= 3)) return 4
    if (value.length >= min + 2 || kinds >= 3) return 3
    return 2
  }
}
