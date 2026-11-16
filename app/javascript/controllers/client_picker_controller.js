import { Controller } from "@hotwired/stimulus"

// Choose a client by searching (CLI-02), or add one: "New client" asks the page's quick-create
// modal to open (a cancelable "client-picker:new" carrying this picker's id) and takes the
// client the modal reports for that id ("quick-create:picked"). Both travel via window
// because the modal lives outside the form. The uid goes in a hidden field; when the picker
// is required, the host form won't submit without one. Searches are POSTs, so names and
// phones stay out of URLs.
export default class extends Controller {
  static targets = ["value", "input", "list", "status", "chosen", "chosenName", "chosenDetail", "searchBox"]
  static values = { url: String, required: Boolean }

  connect() {
    this.clients = []
    this.active = -1
    this.request = 0
    this.id = `client-picker-${Math.random().toString(36).slice(2)}`
    this.form = this.element.closest("form")
    this.guard = (event) => this.checkChosen(event)
    this.form?.addEventListener("submit", this.guard, true)
    // Typed before this controller loaded (slow phone, cold cache): search now.
    if (document.activeElement === this.inputTarget && this.inputTarget.value.trim() !== "") this.search()
  }

  disconnect() {
    this.cancel()
    this.form?.removeEventListener("submit", this.guard, true)
  }

  // A hidden field can't be `required`, so block the host form's submit here instead.
  checkChosen(event) {
    if (!this.requiredValue || this.valueTarget.value) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.inputTarget.setCustomValidity("Choose a client, or add a new one.")
    this.inputTarget.reportValidity()
  }

  search() {
    clearTimeout(this.timer)
    const query = this.inputTarget.value.trim()
    if (query === "") return this.close()
    this.timer = setTimeout(() => this.fetch(query), 200)
  }

  async fetch(query) {
    const request = ++this.request
    const body = new FormData()
    body.append("q", query)
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(response.statusText)
      const { clients } = await response.json()
      if (request === this.request) this.render(clients, query)
    } catch {
      if (request === this.request) this.render([], query, "Couldn't search clients. Check your connection and try again.")
    }
  }

  render(clients, query, emptyText = "No matching clients. Use New client to add one.") {
    this.clients = clients
    this.renderedQuery = query
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
    // Results that land after focus moved away wait until the search box is focused again.
    if (this.element.contains(document.activeElement)) this.show()
    this.statusTarget.textContent = clients.length ? `${clients.length} clients` : emptyText
  }

  // Back in the search box: show the results for what's typed, searching again if the
  // results on hand are for something else.
  reopen() {
    const query = this.inputTarget.value.trim()
    if (query === "") return
    if (query === this.renderedQuery) this.show()
    else this.search()
  }

  keydown(event) {
    // Enter in the search box never submits the host form.
    if (event.key === "Enter" && event.target === this.inputTarget) event.preventDefault()
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
    const request = this.dispatch("new", { detail: { requester: this.id }, cancelable: true })
    if (!request.defaultPrevented) this.statusTarget.textContent = "Adding a client isn't available on this page."
  }

  // From the page's quick-create modal: only the client it added for this picker.
  created(event) {
    if (event.detail?.requester === this.id) this.select(event.detail.client)
  }

  select(client) {
    this.valueTarget.value = client.uid
    this.inputTarget.setCustomValidity("")
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

  // Losing focus only hides the list. A search already under way still finishes, so typing
  // that races a focus change (a validation bubble, a tap elsewhere) isn't dropped.
  blur(event) {
    if (!this.element.contains(event.relatedTarget)) this.hide()
  }

  cancel() {
    clearTimeout(this.timer)
    this.request++
  }

  close() {
    this.cancel()
    this.renderedQuery = null
    this.hide()
  }

  show() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  hide() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
