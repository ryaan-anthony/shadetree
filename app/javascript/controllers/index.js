// Registers every controller under controllers/ from the importmap (like stimulus-loading's
// eagerLoadControllersFrom), then marks <html data-controllers-loaded> once all are in and
// connected, so system tests can wait for the page to be interactive instead of racing a
// cold cache. Stimulus only connects controllers once the DOM is ready, and cached imports
// can finish before that, so the mark also waits for DOMContentLoaded and then one task, by
// which time Stimulus (whose listener was added first) has started.
import { application } from "controllers/application"

const importmap = JSON.parse(document.querySelector("script[type=importmap]")?.textContent || "{}")
const paths = Object.keys(importmap.imports || {}).filter((path) => /^controllers\/.+_controller$/.test(path))
const name = (path) => path.replace(/^controllers\//, "").replace(/_controller$/, "").replace(/\//g, "--").replace(/_/g, "-")

const registered = Promise.allSettled(paths.map((path) => import(path).then((module) => application.register(name(path), module.default))))
const domReady = new Promise((resolve) => {
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", resolve, { once: true })
  else resolve()
})

Promise.all([ registered, domReady ]).then(() => setTimeout(() => { document.documentElement.dataset.controllersLoaded = "" }))
