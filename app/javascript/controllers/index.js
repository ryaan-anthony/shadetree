// Registers every controller under controllers/ from the importmap (like stimulus-loading's
// eagerLoadControllersFrom), then marks <html data-controllers-loaded> once all are in, so
// system tests can wait for the page to be interactive instead of racing a cold cache.
import { application } from "controllers/application"

const importmap = JSON.parse(document.querySelector("script[type=importmap]")?.textContent || "{}")
const paths = Object.keys(importmap.imports || {}).filter((path) => /^controllers\/.+_controller$/.test(path))
const name = (path) => path.replace(/^controllers\//, "").replace(/_controller$/, "").replace(/\//g, "--").replace(/_/g, "-")

Promise.allSettled(paths.map((path) => import(path).then((module) => application.register(name(path), module.default))))
  .then(() => { document.documentElement.dataset.controllersLoaded = "" })
