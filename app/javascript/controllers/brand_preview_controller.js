import { Controller } from "@hotwired/stimulus"

// Live preview for the branding settings (CAT-02): keeps the hex field, color picker and
// preset swatches in step, recolors the sample client page, warns about low contrast with
// the same WCAG thresholds as Branding, and previews a chosen logo before it's uploaded.
export default class extends Controller {
  static targets = ["hex", "picker", "swatch", "warnings", "preview", "previewLogo", "previewMark", "previewName",
    "logoInput", "logoError", "removeLogo", "currentLogo"]
  static values = { maxBytes: Number, types: String, minText: Number, minPage: Number }

  connect() {
    this.savedLogo = this.hasPreviewLogoTarget && !this.previewLogoTarget.hidden ? this.previewLogoTarget.src : null
    this.render()
  }

  disconnect() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }

  pick(event) {
    this.hexTarget.value = event.currentTarget.dataset.color
    this.render()
  }

  picked() {
    this.hexTarget.value = this.pickerTarget.value
    this.render()
  }

  typed() {
    this.render()
  }

  logoChosen() {
    const file = this.logoInputTarget.files[0]
    let problem = null
    if (file && !this.typesValue.split(",").includes(file.type)) problem = "Logo must be a PNG, JPEG or WebP image."
    else if (file && file.size > this.maxBytesValue) problem = `Logo must be smaller than ${Math.round(this.maxBytesValue / 1048576)} MB.`
    this.logoErrorTarget.textContent = problem || ""
    this.logoErrorTarget.hidden = !problem
    this.logoInputTarget.setAttribute("aria-invalid", problem ? "true" : "false")

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = file && !problem ? URL.createObjectURL(file) : null
    this.render()
  }

  render() {
    const color = this.color()
    if (color) {
      const ink = contrast(color, WHITE) >= contrast(color, INK) ? WHITE : INK
      this.previewTarget.style.setProperty("--color-brand", color)
      this.previewTarget.style.setProperty("--color-brand-ink", ink)
      this.previewTarget.style.setProperty("--color-brand-soft", `color-mix(in srgb, ${color} 10%, white)`)
      if (this.pickerTarget.value !== color) this.pickerTarget.value = color
      this.swatchTargets.forEach((swatch) => swatch.setAttribute("aria-pressed", String(swatch.dataset.color === color)))
      this.showWarnings(color, ink)
    } else {
      this.showWarnings(null)
    }

    const removing = this.hasRemoveLogoTarget && this.removeLogoTarget.checked
    const logo = this.objectUrl || (removing ? null : this.savedLogo)
    this.previewLogoTarget.hidden = !logo
    if (logo) this.previewLogoTarget.src = logo
    this.previewMarkTarget.hidden = !!logo
    this.previewNameTarget.hidden = !!logo
  }

  // The hex field's value as #rrggbb, or null while it isn't one yet.
  color() {
    let value = this.hexTarget.value.trim().toLowerCase()
    if (/^[0-9a-f]{6}$/.test(value)) value = `#${value}`
    return /^#[0-9a-f]{6}$/.test(value) ? value : null
  }

  showWarnings(color, ink) {
    const messages = []
    if (!color) messages.push("Enter a color like #047857.")
    else {
      if (contrast(color, ink) < this.minTextValue) messages.push("Button text may be hard to read on this color. Pick a darker or lighter shade.")
      if (contrast(color, WHITE) < this.minPageValue) messages.push("This color is light against a white page, so links and outlines may be hard to see.")
    }
    this.warningsTarget.replaceChildren(...messages.map((message) => {
      const item = document.createElement("li")
      item.className = "flex items-start gap-2 text-sm2 text-warning"
      item.textContent = message
      return item
    }))
  }
}

const WHITE = "#ffffff"
const INK = "#0f172a"

function luminance(hex) {
  const channels = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}

function contrast(a, b) {
  const [high, low] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (high + 0.05) / (low + 0.05)
}
