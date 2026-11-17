import { Controller } from "@hotwired/stimulus"

// Search-as-you-type over the catalog (CAT-03). Before typing it shows recently picked items,
// remembered per business in localStorage as uids only and re-fetched, so prices are current
// and archived items drop out. Recents are a convenience; storage may be empty or blocked.
export default class extends Controller {
  static targets = ["input", "list", "status"]
  static values = { url: String, storageKey: String }

  connect() {
    this.items = []
    this.active = -1
    this.request = 0
    // Typed before this controller loaded (slow phone, cold cache): search now.
    if (document.activeElement === this.inputTarget && this.inputTarget.value.trim() !== "") this.search()
  }

  disconnect() {
    this.cancelPending()
  }

  open() {
    if (this.inputTarget.value.trim() !== "") return this.search()
    const uids = this.recent()
    if (uids.length) this.fetch({ uids: uids.join(",") }, "Recently used")
    else this.close({ clear: true })
  }

  search() {
    clearTimeout(this.timer)
    const query = this.inputTarget.value.trim()
    if (query === "") return this.open()
    this.timer = setTimeout(() => this.fetch({ q: query }), 150)
  }

  // Each request gets a number; closing the list or a newer request makes older ones stale,
  // so a slow response can't reopen a dismissed list or overwrite newer results.
  async fetch(params, heading = null) {
    const request = ++this.request
    const url = new URL(this.urlValue, window.location.origin)
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value))
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.statusText)
      const { items } = await response.json()
      if (request === this.request) this.render(items, heading)
    } catch {
      if (request === this.request) this.render([], null, "Couldn't search the catalog. Check your connection and try again.")
    }
  }

  render(items, heading = null, emptyText = "No matching items. Type the line by hand instead.") {
    this.items = items
    this.active = -1
    this.listTarget.replaceChildren()
    if (heading && items.length) {
      const label = document.createElement("li")
      label.className = "menu-label"
      label.setAttribute("role", "presentation")
      label.textContent = heading
      this.listTarget.append(label)
    }
    items.forEach((item, index) => {
      const option = document.createElement("li")
      option.id = `${this.listTarget.id}-${index}`
      option.className = "menu-item cursor-pointer justify-between"
      option.setAttribute("role", "option")
      option.dataset.index = index
      option.addEventListener("mousedown", (event) => { event.preventDefault(); this.pick(index) })
      const name = document.createElement("span")
      name.className = "min-w-0 truncate"
      name.textContent = item.name
      if (item.category) {
        const category = document.createElement("span")
        category.className = "ml-1.5 text-muted"
        category.textContent = item.category
        name.append(category)
      }
      const price = document.createElement("span")
      price.className = "money text-muted"
      price.textContent = item.price ? `${item.price} / ${item.unit}` : "Price on quote"
      option.append(name, price)
      this.listTarget.append(option)
    })
    if (!items.length && this.inputTarget.value.trim() !== "") {
      const empty = document.createElement("li")
      empty.className = "px-3 py-2 text-sm2 text-muted"
      empty.textContent = emptyText
      this.listTarget.append(empty)
    }
    // Results that land after focus moved away stay hidden; focusing the box again re-searches.
    const show = this.listTarget.children.length > 0 && this.element.contains(document.activeElement)
    this.listTarget.hidden = !show
    this.inputTarget.setAttribute("aria-expanded", String(show))
    this.statusTarget.textContent = items.length ? `${items.length} items` : ""
  }

  keydown(event) {
    if (this.listTarget.hidden) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.highlight((this.active + step + this.items.length) % this.items.length)
    } else if (event.key === "Enter" && this.active >= 0) {
      event.preventDefault()
      this.pick(this.active)
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  highlight(index) {
    this.active = index
    this.listTarget.querySelectorAll("[role=option]").forEach((option) => {
      const on = Number(option.dataset.index) === index
      option.setAttribute("aria-selected", String(on))
      if (on) {
        this.inputTarget.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({ block: "nearest" })
      }
    })
  }

  pick(index) {
    const item = this.items[index]
    if (!item) return
    this.remember(item)
    this.dispatch("pick", { detail: item })
    this.inputTarget.value = ""
    this.close()
  }

  // Losing focus only hides the list. A search already under way still finishes, so typing
  // that races a focus change isn't dropped.
  blur(event) {
    if (!this.element.contains(event.relatedTarget)) this.hide()
  }

  cancelPending() {
    clearTimeout(this.timer)
    this.request++
  }

  close({ clear = false } = {}) {
    this.cancelPending()
    if (clear) {
      this.items = []
      this.active = -1
      this.listTarget.replaceChildren()
    }
    this.hide()
  }

  hide() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  recent() {
    try {
      const uids = JSON.parse(localStorage.getItem(this.storageKeyValue))
      return Array.isArray(uids) ? uids.filter((uid) => typeof uid === "string") : []
    } catch {
      return []
    }
  }

  remember(item) {
    try {
      const uids = [item.uid, ...this.recent().filter((uid) => uid !== item.uid)].slice(0, 5)
      localStorage.setItem(this.storageKeyValue, JSON.stringify(uids))
    } catch {
      // Storage can be full or blocked; recents are only a convenience.
    }
  }
}
