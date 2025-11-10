import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="brand-preview"
export default class extends Controller {
  static targets = ["preview", "previewButton", "previewIcon", "previewLogo", "colorInput", "logoInput"]

  connect() {
    this.updatePreview()
  }

  updateColor(event) {
    this.updatePreview()
  }

  updateLogo(event) {
    this.updatePreview()
  }

  updatePreview() {
    const color = this.hasColorInputTarget ? this.colorInputTarget.value : "#059669"
    const logoUrl = this.hasLogoInputTarget ? this.logoInputTarget.value : ""

    if (this.hasPreviewTarget) {
      this.previewTarget.style.borderColor = color
    }

    if (this.hasPreviewButtonTarget) {
      this.previewButtonTarget.style.backgroundColor = color
    }

    if (this.hasPreviewIconTarget) {
      this.previewIconTarget.style.backgroundColor = color
    }

    if (this.hasPreviewLogoTarget && logoUrl) {
      this.previewLogoTarget.src = logoUrl
      this.previewLogoTarget.style.display = "block"
      if (this.hasPreviewIconTarget) {
        this.previewIconTarget.style.display = "none"
      }
    } else if (this.hasPreviewLogoTarget) {
      this.previewLogoTarget.style.display = "none"
      if (this.hasPreviewIconTarget) {
        this.previewIconTarget.style.display = "flex"
      }
    }
  }

  selectPresetColor(event) {
    const color = event.currentTarget.dataset.color
    if (this.hasColorInputTarget) {
      this.colorInputTarget.value = color
      this.updatePreview()
    }
  }
}

