/* Shadetree mockups — shared shell and interactions.
   Staff pages declare <body data-app="staff" data-nav="quotes" data-crumbs="Quotes:quotes.html|Q-1042">
   and get the sidebar, top bar, command palette, "New" menu, notifications and support dialog. */
(function () {
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const icon = (n, cls) => `<i class="i ${cls || ""}" data-i="${n}"></i>`;

  const NAV = [
    { id: "home", label: "Home", href: "dashboard.html", icon: "home" },
    { id: "requests", label: "Requests", href: "requests.html", icon: "inbox", count: 3 },
    { id: "schedule", label: "Schedule", href: "schedule.html", icon: "calendar" },
    { id: "clients", label: "Clients", href: "clients.html", icon: "users" },
    { id: "quotes", label: "Quotes", href: "quotes.html", icon: "quote" },
    { id: "jobs", label: "Jobs", href: "jobs.html", icon: "job" },
    { id: "invoices", label: "Invoices", href: "invoices.html", icon: "invoice" },
    { group: "Business" },
    { id: "settings", label: "Settings", href: "settings.html", icon: "settings" }
  ];

  function sidebar(active) {
    const items = NAV.map((n) =>
      n.group
        ? `<div class="side-group">${n.group}</div>`
        : `<a href="${n.href}" class="${n.id === active ? "is-active" : ""}">${icon(n.icon)}<span>${n.label}</span>${n.count ? `<span class="count">${n.count}</span>` : ""}</a>`
    ).join("");
    return `
    <aside class="side" id="side" aria-label="Main navigation">
      <div class="side-top">
        <button class="biz-switch" data-pop="biz-pop" aria-haspopup="menu">
          <span class="biz-logo">OL</span>
          <span class="grow"><span class="biz-name">Oakline Lawn &amp; Landscape</span><br><span class="biz-role">Owner</span></span>
          ${icon("selector", "i-sm")}
        </button>
        <div class="pop" id="biz-pop" style="left:12px;top:62px;width:256px">
          <div class="menu-label">Your businesses</div>
          <a class="menu-item is-active" href="dashboard.html"><span class="biz-logo" style="width:24px;height:24px;font-size:10px;border-radius:6px">OL</span><span class="grow">Oakline Lawn &amp; Landscape<br><span class="t-xs t-muted">Owner</span></span>${icon("check")}</a>
          <a class="menu-item" href="#"><span class="biz-logo" style="width:24px;height:24px;font-size:10px;border-radius:6px;background:#1d4ed8">FC</span><span class="grow">Fernhill Cleaning<br><span class="t-xs t-muted">Admin</span></span></a>
          <div class="menu-sep"></div>
          <a class="menu-item" href="welcome.html">${icon("plus")}Create another business</a>
        </div>
      </div>
      <button class="side-search" data-open="cmdk">${icon("search")}<span>Search or jump to</span><span class="kbd">⌘K</span></button>
      <nav class="side-nav">${items}</nav>
      <div class="side-foot">
        <div class="plan-card">
          <div class="row between"><span>Pro plan</span><a href="plan.html">Manage</a></div>
          <div class="meter dark"><span style="width:27%"></span></div>
          <span>41 of 150 quotes sent this month</span>
        </div>
        <div class="me">
          <span class="avatar av-4">DW</span>
          <div class="grow"><div>Dana Whitaker</div><div class="t-xs">dana@oaklinelawn.com</div></div>
          <button class="icon-btn" style="color:#8390a6" data-pop="me-pop" aria-label="Account menu">${icon("more")}</button>
          <div class="pop" id="me-pop" style="left:150px;bottom:60px;top:auto">
            <a class="menu-item" href="#">${icon("user")}Account settings</a>
            <button class="menu-item" data-open="support">${icon("life-buoy")}Help &amp; support</button>
            <a class="menu-item" href="../marketing/home.html">${icon("log-out")}Sign out</a>
          </div>
        </div>
      </div>
    </aside>`;
  }

  function crumbs(spec) {
    if (!spec) return "";
    const parts = spec.split("|").map((p) => p.split(":"));
    return parts.map(([label, href], i) =>
      i === parts.length - 1 ? `<span class="here truncate">${label}</span>` : `<a href="${href}">${label}</a>${icon("chevron-right")}`
    ).join("");
  }

  function topbar(spec) {
    return `
    <header class="topbar">
      <button class="icon-btn menu-btn" data-toggle-side aria-label="Open navigation">${icon("menu", "i-lg")}</button>
      <nav class="crumbs" aria-label="Breadcrumb">${crumbs(spec)}</nav>
      <div class="tb-actions">
        <button class="icon-btn hide-md" data-open="cmdk" aria-label="Search">${icon("search")}</button>
        <div style="position:relative">
          <button class="icon-btn" data-pop="notif-pop" aria-label="Notifications">${icon("bell")}<span class="pip"></span></button>
          ${notifications()}
        </div>
        <div style="position:relative" class="hide-sm">
          <button class="btn btn-primary" data-pop="new-pop">${icon("plus")}New</button>
          <div class="pop" id="new-pop" style="right:0;top:42px">
            <a class="menu-item" href="quote-builder.html">${icon("quote")}Quote<span class="kbd">Q</span></a>
            <a class="menu-item" href="job.html">${icon("job")}Job<span class="kbd">J</span></a>
            <a class="menu-item" href="invoice.html">${icon("invoice")}Invoice<span class="kbd">I</span></a>
            <div class="menu-sep"></div>
            <button class="menu-item" data-open="new-client">${icon("user-plus")}Client<span class="kbd">C</span></button>
            <a class="menu-item" href="requests.html">${icon("inbox")}Request<span class="kbd">R</span></a>
          </div>
        </div>
      </div>
    </header>`;
  }

  function notifications() {
    const n = [
      ["check-circle", "var(--canopy-50)", "var(--canopy)", "Quote Q-1041 approved", "Hannah Brooks approved Spring cleanup — $1,189.74", "8 min ago", true, "quote.html"],
      ["inbox", "var(--blue-50)", "var(--blue)", "New request", "Rosa Delgado asked about weekly mowing", "42 min ago", true, "requests.html"],
      ["dollar", "var(--canopy-50)", "var(--canopy)", "Invoice INV-2207 paid", "Westgate Property Mgmt paid $2,450.00 by card", "2 h ago", false, "invoice.html"],
      ["message", "var(--amber-50)", "var(--amber)", "Changes requested on Q-1038", "“Can you skip the side yard edging?”", "Yesterday", false, "quote.html"]
    ];
    return `<div class="pop notif-pop" id="notif-pop">
      <div class="np-head"><strong class="t-ink">Notifications</strong><button class="btn btn-ghost btn-sm">Mark all read</button></div>
      ${n.map(([ic, bg, fg, t, d, time, unread, href]) => `
        <a class="notif-item ${unread ? "unread" : ""}" href="${href}" style="text-decoration:none;color:inherit">
          <span class="ni-icon" style="background:${bg};color:${fg}">${icon(ic)}</span>
          <span class="grow"><span class="ni-title t-strong">${t}</span><br><span class="t-muted">${d}</span><br><span class="t-xs t-faint">${time}</span></span>
        </a>`).join("")}
      <div style="padding:10px 14px"><a href="#" class="t-sm">Notification settings</a></div>
    </div>`;
  }

  function globalDialogs() {
    return `
    <div class="scrim" id="scrim"></div>
    <div class="modal cmdk" id="cmdk" role="dialog" aria-label="Search">
      <div class="cmdk-input">${icon("search", "i-lg")}<input placeholder="Search clients, quotes, invoices… or type a command"><span class="kbd">esc</span></div>
      <div class="cmdk-list">
        <div class="menu-label">Quick actions</div>
        <a class="menu-item is-active" href="quote-builder.html">${icon("quote")}Create quote<span class="kbd">Q</span></a>
        <a class="menu-item" href="schedule.html">${icon("calendar")}Open today’s schedule</a>
        <button class="menu-item" data-open="new-client">${icon("user-plus")}Add client</button>
        <div class="menu-label">Recent</div>
        <a class="menu-item" href="client.html">${icon("user")}Hannah Brooks<span class="t-xs t-muted ml-auto">Client</span></a>
        <a class="menu-item" href="quote.html">${icon("quote")}Q-1041 Spring cleanup<span class="t-xs t-muted ml-auto">Approved</span></a>
        <a class="menu-item" href="invoice.html">${icon("invoice")}INV-2209 Westgate Property Mgmt<span class="t-xs t-muted ml-auto">Overdue</span></a>
        <a class="menu-item" href="job.html">${icon("job")}J-0388 Weekly mowing, 14 Alder Ct<span class="t-xs t-muted ml-auto">Scheduled</span></a>
      </div>
      <div class="cmdk-foot"><span><span class="kbd">↑</span> <span class="kbd">↓</span> to move</span><span><span class="kbd">↵</span> to open</span></div>
    </div>

    <div class="drawer" id="new-client" role="dialog" aria-label="New client">
      <div class="drawer-head"><h2 style="font-size:16px">New client</h2><button class="icon-btn" data-close aria-label="Close">${icon("x")}</button></div>
      <div class="drawer-body">
        <div class="field"><label class="label">Name</label><input class="input" placeholder="Person or company" value="Martin Alvarez"></div>
        <div class="grid-2 mt-16">
          <div class="field" style="margin:0"><label class="label">Email</label><input class="input" value="m.alvarez@email.com"></div>
          <div class="field" style="margin:0"><label class="label">Phone</label><input class="input" value="(555) 214-0099"></div>
        </div>
        <div class="banner banner-info mt-12">${icon("info")}<div><strong>Possible match:</strong> “Martin Alvarez” at 9 Birch Rd already exists. <a href="client.html">Use existing client</a></div></div>
        <div class="field mt-16"><label class="label">Service address <span class="opt">(optional)</span></label><input class="input" placeholder="Start typing an address"></div>
        <div class="field"><label class="label">Access notes <span class="opt">(optional)</span></label><input class="input" placeholder="Gate code, pets, parking…"></div>
        <div class="field"><label class="label">Tags <span class="opt">(optional)</span></label><input class="input" placeholder="e.g. residential, weekly"></div>
      </div>
      <div class="drawer-foot"><button class="btn btn-secondary" data-close>Cancel</button><button class="btn btn-primary" data-close data-toast="Client added">Add client</button></div>
    </div>

    <div class="modal" id="support" role="dialog" aria-label="Contact support">
      <div class="modal-head"><div><h2>Contact support</h2><p>We usually reply within a few hours on weekdays. Replies arrive here and by email.</p></div><button class="icon-btn" data-close aria-label="Close">${icon("x")}</button></div>
      <div class="modal-body">
        <div class="field"><label class="label">Topic</label><select class="select"><option>Question</option><option>Something isn’t working</option><option>Billing</option><option>Feature request</option></select></div>
        <div class="field"><label class="label">Subject</label><input class="input" placeholder="What do you need help with?"></div>
        <div class="field"><label class="label">Details</label><textarea class="textarea" placeholder="What happened, and what did you expect?"></textarea></div>
        <p class="help">${icon("paperclip", "i-sm")} The page you were on and your browser details are attached automatically.</p>
      </div>
      <div class="modal-foot"><button class="btn btn-secondary" data-close>Cancel</button><button class="btn btn-primary" data-close data-toast="Request sent to support">Send request</button></div>
    </div>
    <div class="toast" id="toast" role="status">${icon("check-circle")}<span></span></div>`;
  }

  function buildShell() {
    const body = document.body;
    if (body.dataset.app !== "staff") return;
    const content = Array.from(body.childNodes).filter((n) => !(n.tagName === "SCRIPT"));
    const shell = document.createElement("div");
    shell.className = "shell";
    shell.innerHTML = sidebar(body.dataset.nav) + `<div class="main">${topbar(body.dataset.crumbs)}</div>`;
    const main = shell.querySelector(".main");
    content.forEach((n) => main.appendChild(n));
    if (location.hash === "#impersonate") {
      const ban = document.createElement("div");
      ban.className = "imp-banner";
      ban.innerHTML = `${icon("eye")}<span><strong>Viewing as Dana Whitaker</strong> (Owner, Oakline Lawn &amp; Landscape) · Read-only · Started by Alex from Shadetree support · ends in 28 min</span><a class="btn btn-secondary btn-sm" href="../operator/console.html">Stop viewing</a>`;
      main.insertBefore(ban, main.firstChild);
    }
    body.prepend(shell);
    if (document.querySelector(".mobile-bar") || body.dataset.nofab !== undefined) return;
    const fab = document.createElement("a");
    fab.className = "fab"; fab.href = "quote-builder.html"; fab.setAttribute("aria-label", "New quote");
    fab.innerHTML = icon("plus");
    body.appendChild(fab);
  }

  function ensureGlobals() {
    if (!$("#scrim")) {
      const wrap = document.createElement("div");
      wrap.innerHTML = document.body.dataset.app === "staff"
        ? globalDialogs()
        : `<div class="scrim" id="scrim"></div><div class="toast" id="toast" role="status">${icon("check-circle")}<span></span></div>`;
      Array.from(wrap.children).forEach((c) => document.body.appendChild(c));
    }
  }

  /* ---------- interactions ---------- */
  let openLayer = null;
  function open(id) {
    const el = document.getElementById(id);
    if (!el) return;
    closeAll();
    el.classList.add("is-open");
    if (el.matches(".modal, .drawer, .sheet")) $("#scrim").classList.add("is-open");
    openLayer = el;
    const f = el.querySelector("input, textarea, select");
    if (f) setTimeout(() => f.focus(), 30);
  }
  function closeAll() {
    $$(".modal.is-open, .drawer.is-open, .sheet.is-open, .pop.is-open").forEach((e) => e.classList.remove("is-open"));
    const s = $("#scrim"); if (s) s.classList.remove("is-open");
    openLayer = null;
  }
  function toast(text) {
    const t = $("#toast"); if (!t) return;
    t.querySelector("span").textContent = text;
    t.classList.add("is-open");
    clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove("is-open"), 2600);
  }
  window.mockToast = toast;
  window.mockOpen = open;
  window.mockClose = closeAll;

  document.addEventListener("click", (e) => {
    const opener = e.target.closest("[data-open]");
    const closer = e.target.closest("[data-close]");
    const popBtn = e.target.closest("[data-pop]");
    const toastBtn = e.target.closest("[data-toast]");
    const tab = e.target.closest("[data-tab]");
    const sideBtn = e.target.closest("[data-toggle-side]");

    if (toastBtn) toast(toastBtn.dataset.toast);
    if (sideBtn) { $("#side").classList.toggle("is-open"); return; }
    if (closer) { closeAll(); return; }
    if (opener) { e.preventDefault(); open(opener.dataset.open); return; }
    if (popBtn) {
      e.preventDefault();
      const p = document.getElementById(popBtn.dataset.pop);
      const was = p.classList.contains("is-open");
      $$(".pop.is-open").forEach((x) => x.classList.remove("is-open"));
      if (!was) p.classList.add("is-open");
      return;
    }
    if (tab) {
      const group = tab.closest("[data-tabs]");
      $$("[data-tab]", group).forEach((t) => t.classList.toggle("is-active", t === tab));
      const target = tab.dataset.tab;
      if (target) $$("[data-panel]", document).forEach((p) => {
        if (p.dataset.group === group.dataset.tabs) p.hidden = p.dataset.panel !== target;
      });
    }
    if (e.target.id === "scrim") closeAll();
    if (!e.target.closest(".pop")) $$(".pop.is-open").forEach((x) => x.classList.remove("is-open"));
    if ($("#side") && $("#side").classList.contains("is-open") && !e.target.closest("#side")) $("#side").classList.remove("is-open");
  });
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k" && $("#cmdk")) { e.preventDefault(); open("cmdk"); }
    if (e.key === "Escape") closeAll();
  });

  const SETTINGS = [
    ["Business", [["profile", "Business profile", "settings.html"], ["branding", "Branding", "settings.html#branding"], ["locations", "Locations", "#"], ["hours", "Hours & closures", "#"]]],
    ["Work", [["services", "Services & pricing", "services.html"], ["taxes", "Taxes", "#"], ["request-form", "Request form", "#"], ["documents", "Quote & invoice defaults", "#"]]],
    ["Team", [["team", "Team & roles", "team.html"], ["notifications", "My notifications", "#"]]],
    ["Communication", [["automations", "Automations", "automations.html"], ["templates", "Message templates", "#"]]],
    ["Money", [["payments", "Online payments", "#"], ["plan", "Plan & billing", "plan.html"], ["export", "Export data", "#"]]]
  ];
  function settingsNav(el) {
    const active = el.dataset.settingsNav;
    el.innerHTML = SETTINGS.map(([g, items]) => `<div class="sn-group">${g}</div>` + items.map(([id, label, href]) =>
      `<a href="${href}" class="${id === active ? "is-active" : ""}">${label}</a>`).join("")).join("");
  }

  document.addEventListener("DOMContentLoaded", () => {
    buildShell();
    document.querySelectorAll("[data-settings-nav]").forEach(settingsNav);
    ensureGlobals();
    if (window.renderIcons) window.renderIcons();
    $$("[data-logo-mark]").forEach((el) => { if (!el.innerHTML) el.innerHTML = window.LOGO_MARK; });
  });
})();
