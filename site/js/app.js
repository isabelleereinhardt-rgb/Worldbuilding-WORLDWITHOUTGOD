/* ============================================================
   The Codex — core app
   Router, global search, cross-referencing, reading view,
   galleries, and the local canon assistant.
   ============================================================ */
(function () {
"use strict";

const DB = window.WORLD_DB || { entries: [], entities: [], categories: [], stats: {} };
const SRC = "../source/";               // image + pdf base path
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => (s || "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/* ---------- category visuals ---------- */
const CAT = {
  "Characters":         { icon: "👤", color: "#7c5cff" },
  "Noble Houses":       { icon: "🛡️", color: "#b8893b" },
  "Maps & Locations":   { icon: "🗺️", color: "#3f8f6b" },
  "Religion & Faith":   { icon: "🕯️", color: "#c2603f" },
  "Magic System":       { icon: "✷", color: "#5c8fff" },
  "Timeline & History": { icon: "⏳", color: "#9a6bd0" },
  "Culture & Fashion":  { icon: "🎭", color: "#d0699a" },
  "Books & Stories":    { icon: "📖", color: "#6b8f3f" },
  "Reference & Lexicon":{ icon: "🔖", color: "#6a655c" },
  "Canon & Continuity": { icon: "✓", color: "#3f6f8f" },
};
const catColor = c => (CAT[c] || {}).color || "var(--accent)";
const catIcon = c => (CAT[c] || {}).icon || "•";

/* ---------- indexes ---------- */
const byId = {};
DB.entries.forEach(e => { byId[e.id] = e; e._hay = (e.title + " " + e.text).toLowerCase(); });

// entity match regex (longest first), for cross-linking in reading view
const entitySet = new Set(DB.entities);
const sortedEntities = DB.entities.slice().sort((a, b) => b.length - a.length);
let ENT_RE = null;
if (sortedEntities.length) {
  const pat = sortedEntities.slice(0, 1200).map(s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  try { ENT_RE = new RegExp("\\b(" + pat + ")\\b", "g"); } catch (e) { ENT_RE = null; }
}

/* ---------- state ---------- */
const store = {
  recent: JSON.parse(localStorage.getItem("codex.recent") || "[]"),
  pushRecent(id) {
    this.recent = [id, ...this.recent.filter(x => x !== id)].slice(0, 8);
    localStorage.setItem("codex.recent", JSON.stringify(this.recent));
  }
};

/* ============================================================
   SIDEBAR
   ============================================================ */
function buildNav() {
  const nav = $("#nav");
  const cats = DB.categories.map(c =>
    `<div class="nav-item" data-route="#/browse/${encodeURIComponent(c.name)}">
       <span class="dot" style="background:${catColor(c.name)}"></span>
       <span>${esc(c.name)}</span><span class="count">${c.count}</span>
     </div>`).join("");
  nav.innerHTML = `
    <div class="nav-section">
      <div class="nav-item" data-route="#/"><span>🏠</span><span>Home</span></div>
      <div class="nav-item" data-route="#/maps"><span>🗺️</span><span>Atlas &amp; Galleries</span></div>
      <div class="nav-item" data-route="#/index"><span>🔤</span><span>Name Index</span></div>
    </div>
    <div class="nav-section">
      <div class="nav-title">The Canon</div>${cats}
    </div>
    <div class="nav-section">
      <div class="nav-title">Your Workspace</div>
      <div class="nav-item" data-route="#/docs"><span>📝</span><span>Documents</span></div>
      <div class="nav-item" data-route="#/slides"><span>📊</span><span>Slide Decks</span></div>
    </div>
    <div class="nav-section">
      <div class="nav-title">Data</div>
      <div class="nav-item mini" id="navExport"><span>⤓</span><span>Back up my work</span></div>
      <div class="nav-item mini" id="navImport"><span>⤒</span><span>Restore backup</span></div>
    </div>`;
  $$("#nav .nav-item[data-route]").forEach(el =>
    el.onclick = () => { location.hash = el.dataset.route; if (innerWidth < 860) collapseSidebar(true); });
  $("#navExport").onclick = backupAll;
  $("#navImport").onclick = restoreAll;
}
function markActive() {
  const h = location.hash || "#/";
  $$("#nav .nav-item[data-route]").forEach(el =>
    el.classList.toggle("active", el.dataset.route === h ||
      (el.dataset.route !== "#/" && h.startsWith(el.dataset.route))));
}

/* ============================================================
   READING VIEW — format extracted text into calm sections
   ============================================================ */
const FACT_KEYS = /^(Status|Origin|Founded|Founder|Seat|Faction|Spirit Animal|Colors?|Colours?|Wealth|Military|Religion|Theme Song|House Words|Motto|Sigil|Words|Region|Capital|Population|Ruler|Type|Era|Alignment|Party|Allegiance|Rank|Title|Race|Age|Gender|Born|Died|Domain|Symbol|Element)\s*:/i;
const HEADERS = /^(Quick Facts|Status By Era|Why They Matter|Heraldry|History|Overview|Backstory|Background|Relationships|Notable Members|Members|Appearance|Personality|Abilities|Powers|Culture|Beliefs|Practices|Geography|Economy|Politics|Military|Notes|Summary|Legacy|Family|Lineage|Significance|Description|Keywords|References|Weaknesses|Strengths|Vulnerabilities|Timeline|Origins?|Faith|Worship|Death|Funeral|Fashion|Attire|Locations?)\s*:?\s*$/i;

function crossLink(html) {
  if (!ENT_RE) return html;
  // only link inside text; html here is already escaped plain text
  return html.replace(ENT_RE, m =>
    `<span class="xref" data-subject="${esc(m)}">${m}</span>`);
}

function renderBody(entry) {
  const lines = entry.text.split("\n");
  let out = [], facts = [], para = [], titleSeen = 0;
  const flushPara = () => {
    if (para.length) {
      const t = para.join(" ").trim();
      if (t) out.push(`<p>${crossLink(esc(t))}</p>`);
      para = [];
    }
  };
  const flushFacts = () => {
    if (facts.length) {
      out.push(`<dl class="facts">${facts.join("")}</dl>`);
      facts = [];
    }
  };
  for (let raw of lines) {
    const line = raw.trim();
    if (!line) { flushPara(); continue; }
    if (/^\d{1,3}$/.test(line)) continue;                    // stray page numbers
    // skip the duplicated title lines at the very top
    if (titleSeen < 2 && line.toLowerCase() === entry.title.toLowerCase()) { titleSeen++; continue; }
    // motto in quotes
    if (/^[“"'].{4,}["”']$/.test(line) && out.length < 3) {
      flushPara(); flushFacts();
      out.push(`<div class="motto">${esc(line.replace(/^["“']|["”']$/g, ""))}</div>`);
      continue;
    }
    // section header
    if (HEADERS.test(line) && line.length < 40) {
      flushPara(); flushFacts();
      out.push(`<h3>${esc(line.replace(/:\s*$/, ""))}</h3>`);
      continue;
    }
    // key: value fact
    const fm = line.match(FACT_KEYS);
    if (fm && line.length < 120) {
      flushPara();
      const idx = line.indexOf(":");
      const k = line.slice(0, idx).trim(), v = line.slice(idx + 1).trim();
      facts.push(`<dt>${esc(k)}</dt><dd>${v ? crossLink(esc(v)) : "<span class='faint'>—</span>"}</dd>`);
      continue;
    }
    flushFacts();
    para.push(line);
  }
  flushPara(); flushFacts();
  return out.join("\n");
}

/* backlinks: which other entries mention this one's subject */
function subjectsOf(entry) {
  const subs = new Set([entry.title]);
  const m = entry.title.match(/^House\s+(.+)/);
  if (m) subs.add(m[1]);
  // add coined words from the title that are known entities
  entry.title.split(/\s+/).forEach(w => { if (entitySet.has(w)) subs.add(w); });
  return Array.from(subs);
}
function mentionsOf(name, excludeId) {
  const n = name.toLowerCase();
  return DB.entries.filter(e => e.id !== excludeId && e.type === "pdf" && e._hay.includes(n));
}

/* ============================================================
   VIEWS
   ============================================================ */
const view = $("#view");

function viewHome() {
  const s = DB.stats;
  const cards = DB.categories.map(c => `
    <a class="cat-card" href="#/browse/${encodeURIComponent(c.name)}">
      <span class="bar" style="background:${catColor(c.name)}"></span>
      <span class="ic">${catIcon(c.name)}</span>
      <h3>${esc(c.name)}</h3>
      <div class="n">${c.count} ${c.count === 1 ? "entry" : "entries"}</div>
    </a>`).join("");
  view.innerHTML = `
    <div class="hero">
      <div class="page-kicker">Your worldbuilding codex</div>
      <h1>Everything you've built, calm and findable.</h1>
      <p>One quiet home for every character, house, map, and myth in <em>World Without God</em>.
         Search across it all, follow names wherever they lead, and write new lore right inside it.</p>
      <div class="hero-search">
        <input id="heroSearch" placeholder="Search a name, place, house, or idea…">
        <button class="btn" onclick="location.hash='#/docs'">＋ New document</button>
      </div>
      <div class="stat-row">
        <div><b>${s.entries || 0}</b> entries</div>
        <div><b>${s.entities || 0}</b> cross-linked names</div>
        <div><b>${s.images || 0}</b> images &amp; maps</div>
        <div><b>${(DB.categories || []).length}</b> collections</div>
      </div>
    </div>
    <div class="cat-grid">${cards}</div>`;
  const hs = $("#heroSearch");
  hs.oninput = () => { /* live nudge to overlay */ };
  hs.onkeydown = e => { if (e.key === "Enter" && hs.value.trim()) { openSearch(hs.value.trim()); } };
  hs.onfocus = () => { /* keep inline; overlay on typing */ };
  hs.addEventListener("input", () => { if (hs.value.trim().length >= 2) openSearch(hs.value.trim()); });
}

function viewBrowse(cat) {
  const items = DB.entries.filter(e => e.category === cat)
    .sort((a, b) => a.title.localeCompare(b.title));
  const cards = items.map(e => entryCard(e)).join("") ||
    `<div class="empty-state">Nothing here yet.</div>`;
  view.innerHTML = `<div class="wrap wide">
    <div class="page-kicker">${catIcon(cat)} Collection</div>
    <h1>${esc(cat)}</h1>
    <p class="muted">${items.length} ${items.length === 1 ? "entry" : "entries"}</p>
    <div class="list-grid">${cards}</div>
  </div>`;
  bindCards();
}

function entryCard(e) {
  const preview = e.type === "gallery"
    ? `${e.images.length} images`
    : esc((e.summary || "").slice(0, 160));
  return `<a class="entry-card" href="#/entry/${e.id}">
    <h3>${esc(e.title)}</h3>
    <p>${preview}</p>
    <div class="meta"><span class="dot" style="width:7px;height:7px;border-radius:50%;background:${catColor(e.category)}"></span>
      ${esc(e.category)}${e.type === "pdf" ? " · " + (e.wordcount || 0) + " words" : ""}</div>
  </a>`;
}
function bindCards() { /* anchors handle navigation */ }

function viewEntry(id) {
  const e = byId[id];
  if (!e) { view.innerHTML = `<div class="wrap"><p>Entry not found.</p></div>`; return; }
  store.pushRecent(id);

  if (e.type === "gallery") return viewGallery(e);

  const body = renderBody(e);
  // backlinks
  const subj = e.title;
  const seen = new Set();
  let backs = [];
  subjectsOf(e).forEach(sname => {
    mentionsOf(sname, e.id).forEach(m => { if (!seen.has(m.id)) { seen.add(m.id); backs.push(m); } });
  });
  backs = backs.slice(0, 30);
  const backHtml = backs.length ? `
    <div class="backlinks">
      <h4>↩ Mentioned in ${backs.length} other ${backs.length === 1 ? "entry" : "entries"}</h4>
      ${backs.map(b => `<a href="#/entry/${b.id}">${catIcon(b.category)} ${esc(b.title)} <span class="faint">· ${esc(b.category)}</span></a>`).join("")}
    </div>` : "";

  const relImgs = (e.images || []).length ? galleryHtml(e.images) : "";
  const pdfLink = e.source && e.source.endsWith(".pdf")
    ? `<a class="btn ghost sm" href="${SRC}${encodeURI(e.source)}" target="_blank">📄 Original PDF</a>` : "";

  view.innerHTML = `<div class="wrap">
    <div class="reading">
      <div class="entry-head">
        <div class="page-kicker" style="margin:0">${catIcon(e.category)} ${esc(e.category)}</div>
      </div>
      <h1>${esc(e.title)}</h1>
      <div class="entry-actions">
        <button class="btn sm" id="askAssistant">✦ Ask the assistant about this</button>
        ${pdfLink}
        <button class="btn ghost sm" id="copyText">⧉ Copy text</button>
      </div>
      ${body}
      ${relImgs}
      ${backHtml}
    </div>
  </div>`;

  $$(".xref", view).forEach(x => x.onclick = () => { location.hash = "#/subject/" + encodeURIComponent(x.dataset.subject); });
  bindGallery();
  $("#askAssistant").onclick = () => { openAssistant(); assistantLookup(e.title); };
  $("#copyText").onclick = () => { navigator.clipboard.writeText(e.text); toast("Copied to clipboard"); };
}

/* subject hub: every passage mentioning a name */
function viewSubject(name) {
  const hits = mentionsOf(name, null);
  // rank: entry titled after the name first
  hits.sort((a, b) => {
    const at = a.title.toLowerCase().includes(name.toLowerCase()) ? 0 : 1;
    const bt = b.title.toLowerCase().includes(name.toLowerCase()) ? 0 : 1;
    return at - bt || b._hay.split(name.toLowerCase()).length - a._hay.split(name.toLowerCase()).length;
  });
  const primary = hits.find(h => h.title.toLowerCase() === name.toLowerCase());
  const cards = hits.map(h => {
    const snip = snippet(h.text, name, 240);
    return `<a class="entry-card" href="#/entry/${h.id}" style="min-height:auto">
      <h3>${esc(h.title)}</h3>
      <p>…${snip}…</p>
      <div class="meta"><span class="dot" style="width:7px;height:7px;border-radius:50%;background:${catColor(h.category)}"></span>${esc(h.category)}</div>
    </a>`;
  }).join("");
  view.innerHTML = `<div class="wrap wide">
    <div class="page-kicker">🔗 Cross-reference</div>
    <h1>${esc(name)}</h1>
    <p class="muted">Found in ${hits.length} ${hits.length === 1 ? "entry" : "entries"} across your canon.
      ${primary ? `<a href="#/entry/${primary.id}">Open the main entry →</a>` : ""}</p>
    <div class="list-grid">${cards || `<div class="empty-state">No mentions found.</div>`}</div>
  </div>`;
}

/* ---------- galleries / atlas ---------- */
function galleryHtml(images) {
  return `<div class="gallery">` + images.map(p =>
    `<figure data-full="${SRC}${encodeURI(p)}">
       <img loading="lazy" src="${SRC}${encodeURI(p)}" alt="${esc(p.split('/').pop())}">
       <figcaption>${esc(p.split('/').pop())}</figcaption>
     </figure>`).join("") + `</div>`;
}
function viewGallery(e) {
  view.innerHTML = `<div class="wrap wide">
    <div class="page-kicker">${catIcon(e.category)} Gallery</div>
    <h1>${esc(e.title)}</h1>
    <p class="muted">${e.images.length} images</p>
    ${galleryHtml(e.images)}
  </div>`;
  bindGallery();
}
function viewMaps() {
  const galleries = DB.entries.filter(e => e.type === "gallery");
  const mapDocs = DB.entries.filter(e => e.category === "Maps & Locations" && e.type === "pdf");
  view.innerHTML = `<div class="wrap wide">
    <div class="page-kicker">🗺️ Atlas</div>
    <h1>Atlas &amp; Galleries</h1>
    <p class="muted">Maps, flags, and visual reference plates.</p>
    <div class="list-grid">
      ${galleries.map(e => `<a class="entry-card" href="#/entry/${e.id}">
        <h3>${esc(e.title)}</h3><p>${e.images.length} images</p>
        <div class="meta">🖼️ Gallery</div></a>`).join("")}
      ${mapDocs.map(e => entryCard(e)).join("")}
    </div>
  </div>`;
}
function bindGallery() {
  $$(".gallery figure", view).forEach(f => f.onclick = () => {
    const lb = document.createElement("div");
    lb.className = "lightbox";
    lb.innerHTML = `<img src="${f.dataset.full}">`;
    lb.onclick = () => lb.remove();
    document.body.appendChild(lb);
  });
}

/* ---------- name index ---------- */
function viewIndex() {
  const groups = {};
  DB.entities.forEach(n => {
    const L = n[0].toUpperCase();
    (groups[L] = groups[L] || []).push(n);
  });
  const letters = Object.keys(groups).sort();
  view.innerHTML = `<div class="wrap wide">
    <div class="page-kicker">🔤 Index</div>
    <h1>Name Index</h1>
    <p class="muted">Every cross-linked name in your world. Click any to gather its mentions.</p>
    ${letters.map(L => `<h3 style="font-family:var(--serif);margin-top:26px">${L}</h3>
      <div class="recog">${groups[L].sort().map(n =>
        `<span class="chip" data-subject="${esc(n)}">${esc(n)}</span>`).join("")}</div>`).join("")}
  </div>`;
  $$(".chip[data-subject]", view).forEach(c =>
    c.onclick = () => location.hash = "#/subject/" + encodeURIComponent(c.dataset.subject));
}

/* ============================================================
   GLOBAL SEARCH
   ============================================================ */
function snippet(text, q, len = 160) {
  const t = text.replace(/\s+/g, " ");
  const i = t.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return esc(t.slice(0, len));
  const start = Math.max(0, i - len / 3 | 0);
  const seg = t.slice(start, start + len);
  return esc(seg).replace(new RegExp("(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"), "<mark>$1</mark>");
}
function searchAll(q) {
  q = q.trim().toLowerCase();
  if (!q) return [];
  const terms = q.split(/\s+/);
  const res = [];
  for (const e of DB.entries) {
    const hay = e._hay, title = e.title.toLowerCase();
    let score = 0;
    for (const t of terms) {
      if (!hay.includes(t)) { score = -1; break; }
      if (title.includes(t)) score += 10;
      if (title.startsWith(t)) score += 8;
      score += Math.min(5, (hay.split(t).length - 1)) ;
    }
    if (score > 0) res.push({ e, score });
  }
  res.sort((a, b) => b.score - a.score);
  return res.slice(0, 40).map(r => r.e);
}
let searchSel = 0, searchList = [];
function renderSearch(q) {
  const box = $("#searchResults");
  if (!q.trim()) { box.innerHTML = `<div class="sr-empty">Start typing to search your whole codex.</div>`; return; }
  searchList = searchAll(q);
  if (!searchList.length) { box.innerHTML = `<div class="sr-empty">No matches for “${esc(q)}”.</div>`; return; }
  const groups = {};
  searchList.forEach(e => (groups[e.category] = groups[e.category] || []).push(e));
  let html = "", flat = [];
  Object.keys(groups).forEach(cat => {
    html += `<div class="sr-group">${catIcon(cat)} ${esc(cat)}</div>`;
    groups[cat].forEach(e => {
      const idx = flat.length; flat.push(e);
      html += `<a class="sr-item" data-i="${idx}" href="#/entry/${e.id}">
        <div><span class="t">${esc(e.title)}</span></div>
        <div class="s">${e.type === "gallery" ? e.images.length + " images" : snippet(e.text, q.split(/\s+/)[0], 150)}</div>
      </a>`;
    });
  });
  searchList = flat; searchSel = 0;
  box.innerHTML = html;
  $$(".sr-item", box).forEach(it => {
    it.onclick = () => closeSearch();
    it.onmouseenter = () => { searchSel = +it.dataset.i; hiSearch(); };
  });
  hiSearch();
}
function hiSearch() { $$(".sr-item").forEach((it, i) => it.classList.toggle("sel", i === searchSel)); }
function openSearch(prefill) {
  $("#searchOverlay").hidden = false;
  const inp = $("#searchInput");
  if (prefill != null) inp.value = prefill;
  inp.focus(); inp.select();
  renderSearch(inp.value);
}
function closeSearch() { $("#searchOverlay").hidden = true; }

/* ============================================================
   ASSISTANT — local canon retrieval
   ============================================================ */
function bestEntryFor(name) {
  const n = name.toLowerCase();
  let exact = DB.entries.find(e => e.type === "pdf" && e.title.toLowerCase() === n);
  if (exact) return exact;
  let houses = DB.entries.find(e => e.type === "pdf" && e.title.toLowerCase() === "house " + n);
  if (houses) return houses;
  const hits = mentionsOf(name, null).filter(e => e.type === "pdf");
  if (!hits.length) return null;
  const metaPenalty = e => (e.category === "Canon & Continuity" || e.category === "Reference & Lexicon") ? 1 : 0;
  hits.sort((a, b) =>
    metaPenalty(a) - metaPenalty(b) ||                     // prefer real lore over audit/reference
    (b._hay.split(n).length) - (a._hay.split(n).length));  // then most mentions
  return hits[0];
}
function blurbCard(name) {
  const e = bestEntryFor(name);
  if (!e) return `<div class="blurb"><div class="bt">${esc(name)}</div>
    <div class="bs faint">No canon entry yet — this name isn't in your uploaded lore.</div></div>`;
  const sentence = firstSentenceWith(e.text, name) || e.summary;
  const others = mentionsOf(name, e.id).length;
  return `<div class="blurb">
    <div class="bt">${catIcon(e.category)} ${esc(name)}</div>
    <div class="bc">${esc(e.category)}</div>
    <div class="bs">${esc((sentence || "").slice(0, 300))}${sentence && sentence.length > 300 ? "…" : ""}</div>
    <div class="bl"><b>Source:</b> ${esc(e.title)}${others ? ` · also in <b>${others}</b> other ${others === 1 ? "entry" : "entries"}` : ""}</div>
    <div style="margin-top:8px;display:flex;gap:6px">
      <a class="btn sm" href="#/entry/${e.id}">Open entry</a>
      <a class="btn ghost sm" href="#/subject/${encodeURIComponent(name)}">All mentions</a>
    </div>
  </div>`;
}
function firstSentenceWith(text, name) {
  const t = text.replace(/\s+/g, " ");
  const i = t.toLowerCase().indexOf(name.toLowerCase());
  if (i < 0) return null;
  let start = t.lastIndexOf(".", i); start = start < 0 ? Math.max(0, i - 40) : start + 1;
  let end = t.indexOf(".", i + name.length); end = end < 0 ? Math.min(t.length, i + 220) : end + 1;
  return t.slice(start, end).trim();
}
function assistantLookup(q) {
  const body = $("#assistantBody");
  q = (q || "").trim();
  if (!q) { assistantIdle(); return; }
  // find matching entity names
  const ql = q.toLowerCase();
  const matches = DB.entities.filter(n => n.toLowerCase().includes(ql)).slice(0, 6);
  const exactEntry = DB.entries.find(e => e.type === "pdf" && e.title.toLowerCase().includes(ql));
  const names = [];
  if (exactEntry) names.push(exactEntry.title);
  matches.forEach(m => { if (!names.includes(m)) names.push(m); });
  if (!names.length) {
    body.innerHTML = `<div class="assistant-hint">Nothing in your canon matches “${esc(q)}” yet.<br>Try a character, house, or place name.</div>`;
    return;
  }
  body.innerHTML = names.slice(0, 5).map(blurbCard).join("");
  bindAssistantLinks();
}
function assistantIdle() {
  $("#assistantBody").innerHTML = `<div class="assistant-hint">
    ✦ I read only what <b>you've</b> written.<br><br>
    Look up any name to get an instant blurb pulled straight from your canon —
    or open a Document and I'll recognise names as you type them.</div>`;
}
// recognise entities inside a block of text the user is writing
function assistantScan(text) {
  const found = [];
  const seen = new Set();
  if (ENT_RE) {
    ENT_RE.lastIndex = 0;
    let m;
    while ((m = ENT_RE.exec(text)) && found.length < 12) {
      const w = m[1];
      if (!seen.has(w)) { seen.add(w); found.push(w); }
    }
  }
  const body = $("#assistantBody");
  if (!found.length) {
    body.innerHTML = `<div class="assistant-hint">Keep writing — as you mention names from your world, their blurbs appear here.</div>`;
    return;
  }
  body.innerHTML = `<div class="faint" style="font-size:11px;text-transform:uppercase;letter-spacing:.06em">Recognised in your text</div>
    <div class="recog">${found.map(n => `<span class="chip" data-name="${esc(n)}">${esc(n)}</span>`).join("")}</div>
    <div id="assistantFocus"></div>`;
  $$(".recog .chip", body).forEach(c => c.onclick = () => {
    $("#assistantFocus").innerHTML = blurbCard(c.dataset.name); bindAssistantLinks();
  });
  // auto-show the last recognised name
  $("#assistantFocus").innerHTML = blurbCard(found[found.length - 1]);
  bindAssistantLinks();
}
function bindAssistantLinks() {
  $$("#assistantBody a[href^='#/']").forEach(a => a.onclick = () => { if (innerWidth < 860) {} });
}
window.CodexAssistant = { scan: assistantScan, lookup: assistantLookup, open: openAssistant };

function openAssistant() { $("#app").classList.add("assist-open"); $("#assistant").hidden = false; }
function closeAssistant() { $("#app").classList.remove("assist-open"); $("#assistant").hidden = true; }

/* ============================================================
   BACKUP / RESTORE (documents + slides in localStorage)
   ============================================================ */
function backupAll() {
  const data = {};
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith("codex.")) data[k] = localStorage.getItem(k);
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "codex-backup-" + new Date().toISOString().slice(0, 10) + ".json";
  a.click();
  toast("Backup downloaded");
}
function restoreAll() {
  const inp = document.createElement("input");
  inp.type = "file"; inp.accept = "application/json";
  inp.onchange = () => {
    const f = inp.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = () => {
      try {
        const data = JSON.parse(r.result);
        Object.keys(data).forEach(k => localStorage.setItem(k, data[k]));
        toast("Backup restored"); route();
      } catch (e) { toast("Could not read that file"); }
    };
    r.readAsText(f);
  };
  inp.click();
}

/* ---------- toast ---------- */
let toastT;
function toast(msg) {
  let el = $("#toast");
  if (!el) { el = document.createElement("div"); el.id = "toast";
    el.style.cssText = "position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:10px 18px;border-radius:20px;font-size:13px;z-index:300;box-shadow:var(--shadow)";
    document.body.appendChild(el); }
  el.textContent = msg; el.style.opacity = "1";
  clearTimeout(toastT); toastT = setTimeout(() => el.style.opacity = "0", 1800);
}
window.toast = toast;

/* ============================================================
   ROUTER
   ============================================================ */
function route() {
  const h = location.hash || "#/";
  const [path, arg] = [h.replace(/^#\//, "").split("/")[0], decodeURIComponent(h.split("/").slice(2).join("/") || "")];
  view.scrollTop = 0;
  if (h === "#/" || path === "") viewHome();
  else if (path === "browse") viewBrowse(arg);
  else if (path === "entry") viewEntry(h.split("/")[2]);
  else if (path === "subject") viewSubject(arg);
  else if (path === "maps") viewMaps();
  else if (path === "index") viewIndex();
  else if (path === "docs") window.CodexEditor && CodexEditor.list();
  else if (path === "doc") window.CodexEditor && CodexEditor.open(h.split("/")[2]);
  else if (path === "slides") window.CodexEditor && CodexEditor.deckList();
  else if (path === "deck") window.CodexEditor && CodexEditor.deckOpen(h.split("/")[2]);
  else viewHome();
  markActive();
}

/* ============================================================
   INIT
   ============================================================ */
function collapseSidebar(force) {
  const app = $("#app");
  if (force === true) app.classList.add("sidebar-collapsed");
  else if (force === false) app.classList.remove("sidebar-collapsed");
  else app.classList.toggle("sidebar-collapsed");
}

function init() {
  buildNav();
  $("#app").classList.remove("loading");
  route();
  window.addEventListener("hashchange", route);

  // theme
  const savedTheme = localStorage.getItem("codex.theme");
  if (savedTheme) document.documentElement.dataset.theme = savedTheme;
  $("#themeToggle").onclick = () => {
    const t = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = t;
    localStorage.setItem("codex.theme", t);
  };

  // sidebar
  $("#sidebarToggle").onclick = () => collapseSidebar();
  if (innerWidth < 860) collapseSidebar(true);

  // assistant
  $("#assistantToggle").onclick = () => $("#assistant").hidden ? openAssistant() : closeAssistant();
  $("#assistantClose").onclick = closeAssistant;
  assistantIdle();
  let aT;
  $("#assistantInput").addEventListener("input", e => {
    clearTimeout(aT); aT = setTimeout(() => assistantLookup(e.target.value), 150);
  });

  // search
  $("#searchOpen").onclick = () => openSearch("");
  const si = $("#searchInput");
  let sT;
  si.addEventListener("input", () => { clearTimeout(sT); sT = setTimeout(() => renderSearch(si.value), 90); });
  si.addEventListener("keydown", e => {
    if (e.key === "ArrowDown") { e.preventDefault(); searchSel = Math.min(searchSel + 1, searchList.length - 1); hiSearch(); scrollSel(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); searchSel = Math.max(searchSel - 1, 0); hiSearch(); scrollSel(); }
    else if (e.key === "Enter") { const e2 = searchList[searchSel]; if (e2) { location.hash = "#/entry/" + e2.id; closeSearch(); } }
    else if (e.key === "Escape") closeSearch();
  });
  $("#searchOverlay").addEventListener("click", e => { if (e.target.id === "searchOverlay") closeSearch(); });

  // global keys
  window.addEventListener("keydown", e => {
    if ((e.ctrlKey || e.metaKey) && (e.key === "k" || e.key === "K")) { e.preventDefault(); openSearch(""); }
    if ((e.ctrlKey || e.metaKey) && (e.key === "f" || e.key === "F") && !isEditing(e.target)) { e.preventDefault(); openSearch(""); }
    if (e.key === "Escape") { closeSearch(); $$(".lightbox").forEach(l => l.remove()); }
  });
}
function scrollSel() { const el = $$(".sr-item")[searchSel]; if (el) el.scrollIntoView({ block: "nearest" }); }
function isEditing(t) { return t && (t.isContentEditable || /input|textarea/i.test(t.tagName)); }

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
else init();

window.Codex = { DB, byId, mentionsOf, bestEntryFor, SRC };
})();
