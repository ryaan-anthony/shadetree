import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="operating-hours"
export default class extends Controller {
  static targets = ["day", "summary"]

  connect() {
    this.updateSummary()
  }

  toggleDay(event) {
    this.updateSummary()
  }

  updateTime(event) {
    this.updateSummary()
  }

  updateSummary() {
    if (!this.hasSummaryTarget) return

    const days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    const dayNames = {
      monday: "Mon",
      tuesday: "Tue",
      wednesday: "Wed",
      thursday: "Thu",
      friday: "Fri",
      saturday: "Sat",
      sunday: "Sun"
    }

    const schedule = []

    days.forEach(day => {
      const checkbox = this.element.querySelector(`#${day}_enabled`)
      const startTime = this.element.querySelector(`#${day}_start`)
      const endTime = this.element.querySelector(`#${day}_end`)

      if (checkbox && checkbox.checked && startTime && endTime) {
        schedule.push({
          day: dayNames[day],
          start: startTime.value,
          end: endTime.value
        })
      } else if (checkbox && !checkbox.checked) {
        schedule.push({
          day: dayNames[day],
          closed: true
        })
      }
    })

    // Update summary display
    let summaryHTML = ""
    schedule.forEach(item => {
      if (item.closed) {
        summaryHTML += `<div class="text-sm"><span class="font-medium">${item.day}:</span> <span class="text-gray-500">Closed</span></div>`
      } else {
        summaryHTML += `<div class="text-sm"><span class="font-medium">${item.day}:</span> ${item.start} - ${item.end}</div>`
      }
    })

    this.summaryTarget.innerHTML = summaryHTML
  }
}

