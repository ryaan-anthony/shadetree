import { Controller } from "@hotwired/stimulus"

// Choose a client by searching (CLI-02), or add one: "New client" asks the page's quick-create
// modal to open (client-picker:new) and takes the client it reports (client-picked:picked).
// Both travel via window because the modal lives outside the form. The uid goes in a hidden
// field.
export default class extends Controller {
  static targets = ["value", "input", "list", "status", "chosen", "chosenName", "chosenDetail", "searchBox"]
  static values = { url: String }

  connect() {
    this.clients = []
    this.active = -1
    this.request = 0
  }

  disconnect() {
    this.cancel()
  }

  search() {
    clearTimeout(this.timer)
    const query = this.inputTarget.value.trim()
    if (query === "") return this.close()
    this.timer = setTimeout(() => this.fetch(query), 200)
  }

  async fetch(query) {
    const request = ++this.request
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.statusText)
      const { clients } = await response.json()
      if (request === this.request) this.render(clients)
    } catch {
      if (request === this.request) this.render([], "Couldn't search clients. Check your connection and try again.")
    }
  }

  render(clients, emptyText = "No matching clients. Use New client to add one.") {
    this.clients = clients
    this.active = -1
    this.listTarget.replaceChildren()
    clients.forEach((client, index) => {
      const option = document.createElement("li")
      option.id = `${this.listTarget.id}-${index}`
      option.className = "menu-item cursor-pointer flex-col items-start gap-0"
      option.setAttribute("role", "option")
      option.dataset.index = index
      option.addEventListener("mousedown", (event) => { event.preventDefault(); this.pick(index) })
      const name = document.createElement("span")
      name.className = "font-semibold text-ink"
      name.textContent = client.company ? `${client.name} · ${client.company}` : client.name
      const detail = document.createElement("span")
      detail.className = "text-sm2 text-muted"
      detail.textContent = [client.contact, client.property].filter(Boolean).join(" · ")
      option.append(name, detail)
      this.listTarget.append(option)
    })
    if (!clients.length) {
      const empty = document.createElement("li")
      empty.className = "px-3 py-2 text-sm2 text-muted"
      empty.textContent = emptyText
      this.listTarget.append(empty)
    }
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.statusTarget.textContent = clients.length ? `${clients.length} clients` : emptyText
  }

  keydown(event) {
    if (this.listTarget.hidden) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!this.clients.length) return
      const step = event.key === "ArrowDown" ? 1 : -1
      this.highlight((this.active + step + this.clients.length) % this.clients.length)
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
    const client = this.clients[index]
    if (client) this.select(client)
  }

  requestNew() {
    this.close()
    this.awaitingNew = true
    this.dispatch("new")
  }

  // Another picker on the page opened the modal, so its result isn't ours.
  otherRequested(event) {
    if (!this.element.contains(event.target)) this.awaitingNew = false
  }

  // From the quick-create modal, only if this picker asked for it.
  created(event) {
    if (!this.awaitingNew) return
    this.awaitingNew = false
    this.select(event.detail)
  }

  select(client) {
    this.valueTarget.value = client.uid
    this.chosenNameTarget.textContent = client.company ? `${client.name} · ${client.company}` : client.name
    this.chosenDetailTarget.textContent = [client.contact, client.property].filter(Boolean).join(" · ")
    this.chosenTarget.hidden = false
    this.searchBoxTarget.hidden = true
    this.inputTarget.value = ""
    this.close()
    this.statusTarget.textContent = `${client.name} selected`
    this.dispatch("change", { detail: client })
  }

  change() {
    this.valueTarget.value = ""
    this.chosenTarget.hidden = true
    this.searchBoxTarget.hidden = false
    this.inputTarget.focus()
  }

  blur(event) {
    if (!this.element.contains(event.relatedTarget)) this.close()
  }

  cancel() {
    clearTimeout(this.timer)
    this.request++
  }

  close() {
    this.cancel()
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
