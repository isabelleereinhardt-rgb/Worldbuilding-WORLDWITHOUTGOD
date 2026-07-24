/* Map of the World — interactive atlas app */
(function () {
  "use strict";

  // Atlas image space (canonical coordinate system for all layers & markers)
  var W = 7680, H = 3962;
  var MI_PER_PX = 0.7975; // from the map's 600-mile scale bar

  // ---------- local edits (persisted in this browser) ----------
  var LS_EDITS = "bela.edits.v1";    // { placeId: {n,cat,x,y,d,deleted} }
  var LS_CUSTOM = "bela.custom.v1";  // [ {id,n,cat,x,y,d} ]
  var LS_TEXT = "bela.text.v1";      // { key: text }

  function lsLoad(key, fallback) {
    try {
      var v = JSON.parse(localStorage.getItem(key));
      return v === null || v === undefined ? fallback : v;
    } catch (e) { return fallback; }
  }
  function lsSave(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {}
  }

  var edits = lsLoad(LS_EDITS, {});
  var custom = lsLoad(LS_CUSTOM, []);
  var texts = lsLoad(LS_TEXT, {});
  var editMode = false;

  // Merge base data + local edits into the working gazetteer
  function mergedPlaces() {
    var out = [];
    PLACES.forEach(function (p, i) {
      var id = "p" + i;
      var e = edits[id];
      if (e && e.deleted) return;
      var q = { id: id, n: p.n, cat: p.cat, x: p.x, y: p.y, d: p.d, k: p.k };
      if (e) {
        ["n", "cat", "x", "y", "d", "k"].forEach(function (k) {
          if (e[k] !== undefined) q[k] = e[k];
        });
      }
      out.push(q);
    });
    custom.forEach(function (p) { out.push(p); });
    return out;
  }

  // ---------- map ----------
  var map = L.map("map", {
    crs: L.CRS.Simple,
    minZoom: -3,
    maxZoom: 2.5,
    zoomSnap: 0.25,
    zoomDelta: 0.5,
    attributionControl: false,
    zoomControl: true,
    maxBoundsViscosity: 0.8
  });

  function ll(x, y) { return [H - y, x]; }
  function xyOf(latlng) { return { x: latlng.lng, y: H - latlng.lat }; }

  var atlasBounds = [ll(0, H), ll(W, 0)];
  // Precipitation export shows the same viewport rendered full-bleed at a
  // different zoom; bounds below register it onto the atlas space
  // (alignment computed by cross-correlating landmass silhouettes).
  var popBounds = [ll(63.7, 3956.7), ll(7675.2, 0)];

  var layers = {
    terrain: L.imageOverlay("assets/terrain.jpg", atlasBounds),
    atlas: L.imageOverlay("assets/atlas.jpg", atlasBounds),
    height: L.imageOverlay("assets/height.jpg", atlasBounds),
    precipitation: L.imageOverlay("assets/precipitation.jpg", popBounds),
    borders: L.imageOverlay("assets/borders.jpg", atlasBounds)
  };

  var currentBase = "terrain";
  layers.terrain.addTo(map);
  map.setMaxBounds([ll(-900, H + 700), ll(W + 900, -700)]);
  map.fitBounds(atlasBounds);

  // Prefetch the other layers so switching never shows a blank map
  window.addEventListener("load", function () {
    ["assets/atlas.jpg", "assets/height.jpg", "assets/precipitation.jpg", "assets/borders.jpg"].forEach(function (src) {
      var im = new Image(); im.src = src;
    });
  });

  // ---------- categories ----------
  var CATS = [
    { id: "region", label: "Realms & regions", size: 13 },
    { id: "capital", label: "Capitals", size: 15 },
    { id: "city", label: "Cities & ports", size: 11 },
    { id: "town", label: "Towns & villages", size: 7 },
    { id: "water", label: "Seas & lakes", size: 10 },
    { id: "river", label: "Rivers", size: 8 },
    { id: "island", label: "Islands", size: 10 },
    { id: "forest", label: "Forests", size: 10 },
    { id: "territory", label: "Sacred territories", size: 9 },
    { id: "landmark", label: "Landmarks", size: 9 }
  ];
  var TOWN_MIN_ZOOM = -0.75; // towns unclutter at low zoom

  function catLabel(id) {
    for (var i = 0; i < CATS.length; i++) if (CATS[i].id === id) return CATS[i].label;
    return id;
  }
  function catSize(id) {
    for (var i = 0; i < CATS.length; i++) if (CATS[i].id === id) return CATS[i].size;
    return 9;
  }

  var groups = {};   // cat id -> layerGroup
  var enabled = {};  // cat id -> checkbox state
  var markers = [];  // { place, marker }

  CATS.forEach(function (c) {
    groups[c.id] = L.layerGroup();
    enabled[c.id] = true;
  });

  // ---------- text-to-speech ----------
  var speechOK = ("speechSynthesis" in window);
  function speakPlace(p) {
    if (!speechOK) return;
    window.speechSynthesis.cancel();
    var parts = [p.n];
    if (p.d) parts.push(p.d);
    var u = new SpeechSynthesisUtterance(parts.join(". "));
    u.rate = 0.95;
    u.pitch = 1;
    u.lang = "en-US"; // name and description read in English; names spoken as written
    window.speechSynthesis.speak(u);
  }

  // ---------- marker construction ----------
  function viewPopupContent(p) {
    var div = document.createElement("div");
    var html = '<div class="popup-name">' + esc(p.n) + "</div>" +
      '<div class="popup-cat">' + esc(catLabel(p.cat)) + "</div>" +
      (p.d ? '<div class="popup-desc">' + esc(p.d) + "</div>" : "");
    div.innerHTML = html;
    if (speechOK) {
      var sb = document.createElement("button");
      sb.className = "pbtn audio-btn";
      sb.type = "button";
      sb.title = "Read aloud";
      sb.innerHTML = "🔊 Read aloud";
      sb.addEventListener("click", function () { speakPlace(p); });
      div.appendChild(sb);
    }
    if (editMode) {
      var btn = document.createElement("button");
      btn.className = "pbtn";
      btn.textContent = "✎ Edit";
      btn.addEventListener("click", function () { openEditor(p); });
      div.appendChild(btn);
    }
    return div;
  }

  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function makeMarker(p) {
    var size = catSize(p.cat);
    var icon;
    if (p.cat === "capital") {
      icon = L.divIcon({
        className: "capital-star",
        html: "\u2605",
        iconSize: [18, 18],
        iconAnchor: [9, 10]
      });
    } else {
      icon = L.divIcon({
        className: "dot dot-" + p.cat,
        iconSize: [size, size]
      });
    }
    var m = L.marker(ll(p.x, p.y), {
      icon: icon,
      title: p.n,
      draggable: editMode
    });
    m.bindPopup(function () { return viewPopupContent(p); });
    m.bindTooltip(p.n, { className: "place-tip", direction: "top", offset: [0, -6] });
    if (editMode) {
      m.on("dragend", function () {
        var xy = xyOf(m.getLatLng());
        applyEdit(p.id, { x: Math.round(xy.x), y: Math.round(xy.y) });
      });
    }
    return m;
  }

  function buildMarkers() {
    CATS.forEach(function (c) { groups[c.id].clearLayers(); });
    markers = [];
    mergedPlaces().forEach(function (p) {
      if (!groups[p.cat]) return;
      var m = makeMarker(p);
      m.addTo(groups[p.cat]);
      markers.push({ place: p, marker: m });
    });
    updateCounts();
    refreshGroups();
    if (typeof refreshDatalist === "function" && document.getElementById("place-list")) {
      try { refreshDatalist(); } catch (e) {}
    }
  }

  function refreshGroups() {
    CATS.forEach(function (c) {
      var show = enabled[c.id] &&
        !(c.id === "town" && map.getZoom() < TOWN_MIN_ZOOM);
      if (show && !map.hasLayer(groups[c.id])) map.addLayer(groups[c.id]);
      if (!show && map.hasLayer(groups[c.id])) map.removeLayer(groups[c.id]);
    });
  }
  map.on("zoomend", refreshGroups);
  map.on("popupclose", function () { if (speechOK) window.speechSynthesis.cancel(); });

  // ---------- category toggle UI ----------
  var catBox = document.getElementById("cat-toggles");
  CATS.forEach(function (c) {
    var lab = document.createElement("label");
    lab.innerHTML = '<input type="checkbox" checked data-cat="' + c.id + '">' +
      '<span class="swatch dot-' + c.id + '"></span>' + c.label +
      '<span class="count" data-count="' + c.id + '"></span>';
    catBox.appendChild(lab);
  });
  catBox.addEventListener("change", function (e) {
    var cat = e.target.getAttribute("data-cat");
    if (!cat) return;
    enabled[cat] = e.target.checked;
    refreshGroups();
  });
  function updateCounts() {
    var counts = {};
    mergedPlaces().forEach(function (p) { counts[p.cat] = (counts[p.cat] || 0) + 1; });
    CATS.forEach(function (c) {
      var el = document.querySelector('[data-count="' + c.id + '"]');
      if (el) el.textContent = counts[c.id] || 0;
    });
  }

  // ---------- base layer switching ----------
  document.querySelectorAll('input[name="base"]').forEach(function (r) {
    r.addEventListener("change", function () {
      if (!this.checked) return;
      map.removeLayer(layers[currentBase]);
      currentBase = this.value;
      layers[currentBase].addTo(map);
      layers[currentBase].bringToBack();
      applyCompare();
    });
  });

  // ---------- compare overlay ----------
  var cmpOn = document.getElementById("cmp-on");
  var cmpSel = document.getElementById("cmp-layer");
  var cmpOpacity = document.getElementById("cmp-opacity");
  var cmpActive = null;

  function applyCompare() {
    if (cmpActive && map.hasLayer(cmpActive)) map.removeLayer(cmpActive);
    cmpActive = null;
    if (!cmpOn.checked) return;
    var key = cmpSel.value;
    if (key === currentBase) return;
    cmpActive = layers[key];
    cmpActive.setOpacity(cmpOpacity.value / 100);
    cmpActive.addTo(map);
  }
  cmpOn.addEventListener("change", applyCompare);
  cmpSel.addEventListener("change", applyCompare);
  cmpOpacity.addEventListener("input", function () {
    if (cmpActive) cmpActive.setOpacity(this.value / 100);
  });

  // ---------- search ----------
  var searchInput = document.getElementById("search");
  var resultsList = document.getElementById("search-results");

  function renderResults(q) {
    resultsList.innerHTML = "";
    if (!q) return;
    q = q.toLowerCase();
    var hits = mergedPlaces().filter(function (p) {
      return p.n.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 30);
    hits.forEach(function (p) {
      var li = document.createElement("li");
      li.innerHTML = "<span>" + esc(p.n) + '</span><span class="cat">' +
        esc(catLabel(p.cat)) + "</span>";
      li.addEventListener("click", function () { goTo(p); });
      resultsList.appendChild(li);
    });
  }
  searchInput.addEventListener("input", function () { renderResults(this.value.trim()); });

  function goTo(p) {
    var z = p.cat === "town" ? 0.5 : Math.max(map.getZoom(), -0.5);
    map.flyTo(ll(p.x, p.y), z, { duration: 0.9 });
    var rec = null;
    markers.forEach(function (r) { if (r.place.id === p.id) rec = r; });
    if (rec) {
      enabled[p.cat] = true;
      var box = document.querySelector('input[data-cat="' + p.cat + '"]');
      if (box) box.checked = true;
      map.once("moveend", function () {
        refreshGroups();
        rec.marker.openPopup();
      });
    }
  }

  // ---------- click anywhere: nearest place / add place ----------
  map.on("click", function (e) {
    if (editMode) { openAddForm(e.latlng); return; }
    showNearest(e.latlng);
  });

  function showNearest(latlng) {
    var xy = xyOf(latlng);
    if (xy.x < -50 || xy.x > W + 50 || xy.y < -50 || xy.y > H + 50) return;
    var best = null, bestD = Infinity;
    mergedPlaces().forEach(function (p) {
      var dx = p.x - xy.x, dy = p.y - xy.y;
      var d = Math.sqrt(dx * dx + dy * dy);
      if (d < bestD) { bestD = d; best = p; }
    });
    if (!best) return;
    var mi = Math.round(bestD * MI_PER_PX);
    var div = document.createElement("div");
    div.innerHTML = '<div class="popup-cat">Nearest place ' +
      (mi <= 1 ? "(here)" : "&mdash; about " + mi + " mi away") + "</div>" +
      '<div class="popup-name">' + esc(best.n) + "</div>" +
      '<div class="popup-cat">' + esc(catLabel(best.cat)) + "</div>" +
      (best.d ? '<div class="popup-desc">' + esc(best.d) + "</div>" : "");
    if (speechOK) {
      var sb = document.createElement("button");
      sb.className = "pbtn audio-btn";
      sb.type = "button";
      sb.innerHTML = "🔊 Read aloud";
      sb.addEventListener("click", function () { speakPlace(best); });
      div.appendChild(sb);
    }
    var btn = document.createElement("button");
    btn.className = "pbtn";
    btn.textContent = "Go to " + best.n;
    btn.addEventListener("click", function () { map.closePopup(); goTo(best); });
    div.appendChild(btn);
    L.popup().setLatLng(latlng).setContent(div).openOn(map);
  }

  // ---------- edit mode ----------
  var editToggle = document.getElementById("edit-on");
  editToggle.addEventListener("change", function () {
    editMode = this.checked;
    document.body.classList.toggle("editing", editMode);
    setTextEditable(editMode);
    map.closePopup();
    buildMarkers();
  });

  function applyEdit(id, patch) {
    if (id.charAt(0) === "c") {
      custom.forEach(function (p) {
        if (p.id === id) Object.keys(patch).forEach(function (k) { p[k] = patch[k]; });
      });
      lsSave(LS_CUSTOM, custom);
    } else {
      edits[id] = edits[id] || {};
      Object.keys(patch).forEach(function (k) { edits[id][k] = patch[k]; });
      lsSave(LS_EDITS, edits);
    }
    buildMarkers();
  }

  function deletePlace(id) {
    if (id.charAt(0) === "c") {
      custom = custom.filter(function (p) { return p.id !== id; });
      lsSave(LS_CUSTOM, custom);
    } else {
      edits[id] = edits[id] || {};
      edits[id].deleted = true;
      lsSave(LS_EDITS, edits);
    }
    map.closePopup();
    buildMarkers();
  }

  function editorForm(initial, onSave, onDelete) {
    var div = document.createElement("div");
    div.className = "edit-form";
    div.innerHTML =
      '<label>Name <input type="text" class="ef-name"></label>' +
      '<label>Category <select class="ef-cat"></select></label>' +
      '<label>Description <textarea class="ef-desc" rows="3"></textarea></label>';
    var sel = div.querySelector(".ef-cat");
    CATS.forEach(function (c) {
      var o = document.createElement("option");
      o.value = c.id; o.textContent = c.label;
      sel.appendChild(o);
    });
    div.querySelector(".ef-name").value = initial.n || "";
    sel.value = initial.cat || "town";
    div.querySelector(".ef-desc").value = initial.d || "";
    var row = document.createElement("div");
    row.className = "ef-row";
    var saveB = document.createElement("button");
    saveB.className = "pbtn"; saveB.textContent = "Save";
    saveB.addEventListener("click", function () {
      var name = div.querySelector(".ef-name").value.trim();
      if (!name) { div.querySelector(".ef-name").focus(); return; }
      onSave({
        n: name,
        cat: sel.value,
        d: div.querySelector(".ef-desc").value.trim() || undefined
      });
    });
    row.appendChild(saveB);
    if (onDelete) {
      var delB = document.createElement("button");
      delB.className = "pbtn danger"; delB.textContent = "Delete";
      delB.addEventListener("click", function () {
        if (confirm('Delete "' + initial.n + '"?')) onDelete();
      });
      row.appendChild(delB);
    }
    div.appendChild(row);
    return div;
  }

  function openEditor(p) {
    var form = editorForm(p, function (vals) {
      applyEdit(p.id, vals);
      map.closePopup();
    }, function () { deletePlace(p.id); });
    L.popup({ minWidth: 240 }).setLatLng(ll(p.x, p.y)).setContent(form).openOn(map);
  }

  function openAddForm(latlng) {
    var xy = xyOf(latlng);
    var form = editorForm({ n: "", cat: "town", d: "" }, function (vals) {
      var nearestK = null, bd = Infinity;
      PLACES.forEach(function (q) {
        if (!q.k) return;
        var dd = (q.x - xy.x) * (q.x - xy.x) + (q.y - xy.y) * (q.y - xy.y);
        if (dd < bd) { bd = dd; nearestK = q.k; }
      });
      custom.push({
        id: "c" + Date.now(),
        n: vals.n, cat: vals.cat,
        x: Math.round(xy.x), y: Math.round(xy.y),
        d: vals.d, k: nearestK
      });
      lsSave(LS_CUSTOM, custom);
      map.closePopup();
      buildMarkers();
    });
    var head = document.createElement("div");
    head.className = "popup-cat";
    head.textContent = "New place here";
    form.insertBefore(head, form.firstChild);
    L.popup({ minWidth: 240 }).setLatLng(latlng).setContent(form).openOn(map);
  }

  // ---------- editable site text ----------
  var editableEls = document.querySelectorAll("[data-edit]");
  editableEls.forEach(function (el) {
    var key = el.getAttribute("data-edit");
    if (texts[key]) el.textContent = texts[key];
    el.addEventListener("input", function () {
      texts[key] = el.textContent;
      lsSave(LS_TEXT, texts);
    });
  });
  function setTextEditable(on) {
    editableEls.forEach(function (el) {
      el.setAttribute("contenteditable", on ? "true" : "false");
    });
  }

  // ---------- export & reset ----------
  document.getElementById("export-btn").addEventListener("click", function () {
    var list = mergedPlaces();
    var lines = list.map(function (p) {
      var s = "  { n: " + JSON.stringify(p.n) + ', cat: "' + p.cat +
        '", x: ' + Math.round(p.x) + ", y: " + Math.round(p.y);
      if (p.k) s += ", k: " + JSON.stringify(p.k);
      if (p.d) s += ", d: " + JSON.stringify(p.d);
      return s + " }";
    });
    var biomes = BIOMES.map(function (b) {
      return "  { name: " + JSON.stringify(b.name) + ", color: " + JSON.stringify(b.color) + " }";
    });
    var out = "// Bela world gazetteer.\n" +
      "// Coordinates are pixels in the atlas image space (7680 x 3962), origin top-left.\n" +
      "// Exported from the atlas editor on " + new Date().toISOString().slice(0, 10) + ".\n" +
      "// cat: region | city | town | water | river | island | forest | territory | landmark\n\n" +
      "const PLACES = [\n" + lines.join(",\n") + "\n];\n\n" +
      "const BIOMES = [\n" + biomes.join(",\n") + "\n];\n";
    var blob = new Blob([out], { type: "text/javascript" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "places.js";
    a.click();
    URL.revokeObjectURL(a.href);
  });

  document.getElementById("reset-btn").addEventListener("click", function () {
    if (!confirm("Discard ALL local edits (places and text) and restore the original data?")) return;
    localStorage.removeItem(LS_EDITS);
    localStorage.removeItem(LS_CUSTOM);
    localStorage.removeItem(LS_TEXT);
    location.reload();
  });

  // ---------- biome legend ----------
  var legend = document.getElementById("biome-legend");
  BIOMES.forEach(function (b) {
    var li = document.createElement("li");
    li.innerHTML = '<span class="bs" style="background:' + b.color + '"></span>' + esc(b.name);
    legend.appendChild(li);
  });
  document.querySelectorAll(".collapser").forEach(function (h) {
    h.addEventListener("click", function () {
      var t = document.getElementById(this.getAttribute("data-target"));
      t.classList.toggle("hidden");
      this.classList.toggle("open");
    });
  });

  // ---------- sidebar toggle ----------
  var sidebar = document.getElementById("sidebar");
  document.getElementById("sidebar-toggle").addEventListener("click", function () {
    sidebar.classList.toggle("closed");
    setTimeout(function () { map.invalidateSize(); }, 300);
  });

  // ---------- dynamic mile scale bar ----------
  var ScaleCtl = L.Control.extend({
    options: { position: "bottomleft" },
    onAdd: function () {
      this._div = L.DomUtil.create("div", "bela-scale");
      this._update();
      map.on("zoomend", this._update, this);
      return this._div;
    },
    _update: function () {
      var pxPerMapPx = Math.pow(2, map.getZoom());
      var miPerScreenPx = MI_PER_PX / pxPerMapPx;
      var targetMi = miPerScreenPx * 110;
      var steps = [5, 10, 20, 25, 50, 100, 150, 200, 300, 400, 500, 600, 800, 1000, 1500, 2000, 3000];
      var mi = steps[0];
      for (var i = 0; i < steps.length; i++) {
        if (steps[i] <= targetMi) mi = steps[i];
      }
      var px = Math.round(mi / miPerScreenPx);
      var seg = px / 4;
      var segs = "";
      for (var j = 0; j < 4; j++) {
        segs += '<span class="seg' + (j % 2 ? " alt" : "") + '" style="width:' + seg + 'px"></span>';
      }
      this._div.innerHTML =
        '<div class="scale-labels"><span>0</span><span>' + (mi / 2) + '</span><span>' + mi + " mi</span></div>" +
        '<div class="segbar">' + segs + "</div>";
    }
  });
  map.addControl(new ScaleCtl());


  // ---------- distance tracker ----------
  var distList = document.getElementById("place-list");
  var distA = document.getElementById("dist-a");
  var distB = document.getElementById("dist-b");
  var distOut = document.getElementById("dist-result");

  function refreshDatalist() {
    distList.innerHTML = "";
    mergedPlaces().sort(function (a, b) { return a.n.localeCompare(b.n); })
      .forEach(function (p) {
        var o = document.createElement("option");
        o.value = p.n;
        distList.appendChild(o);
      });
  }

  function findPlace(name) {
    var t = name.trim().toLowerCase();
    if (!t) return null;
    var all = mergedPlaces();
    var i;
    for (i = 0; i < all.length; i++) {
      if (all[i].n.toLowerCase() === t) return all[i];
    }
    var pre = all.filter(function (p) { return p.n.toLowerCase().indexOf(t) === 0; });
    if (pre.length === 1) return pre[0];
    var sub = all.filter(function (p) { return p.n.toLowerCase().indexOf(t) !== -1; });
    if (sub.length === 1) return sub[0];
    return null;
  }

  function sideStatus(input) {
    var raw = input.value.trim();
    if (!raw) return { state: "empty" };
    var p = findPlace(raw);
    if (p) return { state: "ok", place: p };
    return { state: "bad", raw: raw };
  }

  function updateDistance() {
    var a = sideStatus(distA), b = sideStatus(distB);
    if (a.state === "empty" && b.state === "empty") {
      distOut.innerHTML = "";
      return;
    }
    if (a.state === "ok" && b.state === "ok") {
      var pa = a.place, pb = b.place;
      if (pa.n === pb.n) {
        distOut.innerHTML = "Pick two different places.";
        return;
      }
      var mi = Math.round(Math.hypot(pa.x - pb.x, pa.y - pb.y) * MI_PER_PX);
      var foot = Math.max(1, Math.round(mi / 24));
      var horse = Math.max(1, Math.round(mi / 45));
      distOut.innerHTML = "<b>" + esc(pa.n) + "</b> &rarr; <b>" + esc(pb.n) + "</b><br>" +
        '<span class="dist-big">~' + mi + " miles</span> as the crow flies<br>" +
        "Roughly <b>" + foot + " day" + (foot > 1 ? "s" : "") + "</b> on foot or <b>" +
        horse + " day" + (horse > 1 ? "s" : "") + "</b> mounted.";
      return;
    }
    var msgs = [];
    [["From", a], ["To", b]].forEach(function (row) {
      var label = row[0], st = row[1];
      if (st.state === "ok") msgs.push(label + ": &#10003; " + esc(st.place.n));
      else if (st.state === "bad") msgs.push(label + ": no place called &ldquo;" + esc(st.raw) + "&rdquo; &mdash; keep typing or pick from the list");
      else msgs.push(label + ": type or pick a place");
    });
    distOut.innerHTML = msgs.join("<br>");
  }
  distA.addEventListener("input", updateDistance);
  distB.addEventListener("input", updateDistance);
  distA.addEventListener("change", updateDistance);
  distB.addEventListener("change", updateDistance);
  refreshDatalist();


  // ---------- image export of the current view ----------
  var LAYER_INFO = {
    terrain: { src: "assets/terrain.jpg", x0: 0, y0: 0, x1: W, y1: H },
    atlas: { src: "assets/atlas.jpg", x0: 0, y0: 0, x1: W, y1: H },
    height: { src: "assets/height.jpg", x0: 0, y0: 0, x1: W, y1: H },
    precipitation: { src: "assets/precipitation.jpg", x0: 63.7, y0: 0, x1: 7675.2, y1: 3956.7 },
    borders: { src: "assets/borders.jpg", x0: 0, y0: 0, x1: W, y1: H }
  };
  var imgCache = {};
  function loadLayerImage(key) {
    return new Promise(function (resolve, reject) {
      if (imgCache[key] && imgCache[key].complete) return resolve(imgCache[key]);
      var im = new Image();
      im.onload = function () { resolve(im); };
      im.onerror = reject;
      im.src = LAYER_INFO[key].src;
      imgCache[key] = im;
    });
  }

  var MARKER_COLORS = {
    region: "#5b4a8a", capital: "#e8c04a", city: "#b03a2e", town: "#f2e3b0",
    water: "#2e6f8e", river: "#3d85c8", island: "#2e8e64", forest: "#35701f",
    territory: "#8e2e7c", landmark: "#d08a1d"
  };

  function exportViewImage(kind) {
    var mapEl = document.getElementById("map");
    var cw = mapEl.clientWidth, ch = mapEl.clientHeight;
    var scaleUp = 2; // render at 2x for crispness
    var canvas = document.createElement("canvas");
    canvas.width = cw * scaleUp; canvas.height = ch * scaleUp;
    var ctx = canvas.getContext("2d");
    var bounds = map.getBounds();
    var vx0 = bounds.getWest(), vx1 = bounds.getEast();
    var vy0 = H - bounds.getNorth(), vy1 = H - bounds.getSouth(); // atlas y (top..bottom)
    function toCanvas(ax, ay) {
      return [(ax - vx0) / (vx1 - vx0) * canvas.width,
              (ay - vy0) / (vy1 - vy0) * canvas.height];
    }
    ctx.fillStyle = "#c2c69a";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    function drawLayer(key, alpha) {
      return loadLayerImage(key).then(function (im) {
        var inf = LAYER_INFO[key];
        var sx = (vx0 - inf.x0) / (inf.x1 - inf.x0) * im.naturalWidth;
        var sy = (vy0 - inf.y0) / (inf.y1 - inf.y0) * im.naturalHeight;
        var sw = (vx1 - vx0) / (inf.x1 - inf.x0) * im.naturalWidth;
        var sh = (vy1 - vy0) / (inf.y1 - inf.y0) * im.naturalHeight;
        ctx.globalAlpha = alpha;
        ctx.drawImage(im, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
        ctx.globalAlpha = 1;
      });
    }

    var jobs = drawLayer(currentBase, 1);
    if (cmpActive) {
      var cmpKey = cmpSel.value;
      jobs = jobs.then(function () {
        return drawLayer(cmpKey, cmpOpacity.value / 100);
      });
    }
    jobs.then(function () {
      // markers, respecting current visibility rules
      var zoomOK = map.getZoom() >= TOWN_MIN_ZOOM;
      mergedPlaces().forEach(function (p) {
        if (!enabled[p.cat]) return;
        if (p.cat === "town" && !zoomOK) return;
        if (p.x < vx0 - 20 || p.x > vx1 + 20 || p.y < vy0 - 20 || p.y > vy1 + 20) return;
        var pt = toCanvas(p.x, p.y);
        if (p.cat === "capital") {
          ctx.font = (19 * scaleUp) + "px serif";
          ctx.textAlign = "center"; ctx.textBaseline = "middle";
          ctx.lineWidth = 3 * scaleUp; ctx.strokeStyle = "rgba(20,16,8,.85)";
          ctx.strokeText("\u2605", pt[0], pt[1]);
          ctx.fillStyle = MARKER_COLORS.capital;
          ctx.fillText("\u2605", pt[0], pt[1]);
        } else {
          var rr = (catSize(p.cat) / 2 + 1) * scaleUp;
          ctx.beginPath();
          ctx.arc(pt[0], pt[1], rr, 0, Math.PI * 2);
          ctx.fillStyle = MARKER_COLORS[p.cat] || "#888";
          ctx.fill();
          ctx.lineWidth = 1.5 * scaleUp;
          ctx.strokeStyle = "rgba(20,16,8,.85)";
          ctx.stroke();
        }
      });
      var mime = kind === "jpg" ? "image/jpeg" : "image/png";
      canvas.toBlob(function (blob) {
        var a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = "map-view." + (kind === "jpg" ? "jpg" : "png");
        a.click();
        URL.revokeObjectURL(a.href);
      }, mime, 0.92);
    }).catch(function (e) {
      alert("Could not render the view: " + e);
    });
  }

  // ---------- document export ----------
  function groupForDoc() {
    var all = mergedPlaces();
    var opts = {
      settlements: document.getElementById("ex-settlements").checked,
      kingdoms: document.getElementById("ex-kingdoms").checked,
      waters: document.getElementById("ex-waters").checked,
      islands: document.getElementById("ex-islands").checked,
      sacred: document.getElementById("ex-sacred").checked,
      biomes: document.getElementById("ex-biomes").checked,
      mapimg: document.getElementById("ex-map").checked
    };
    var catOk = {};
    if (opts.kingdoms) catOk.region = true;
    if (opts.settlements) { catOk.capital = true; catOk.city = true; catOk.town = true; }
    if (opts.waters) { catOk.water = true; catOk.river = true; }
    if (opts.islands) { catOk.island = true; catOk.forest = true; }
    if (opts.sacred) { catOk.territory = true; catOk.landmark = true; }

    var SECTIONS = [
      ["region", "Regions & provinces"],
      ["capital", "Capital"],
      ["city", "Cities & ports"],
      ["town", "Towns & villages"],
      ["water", "Seas, lakes & bays"],
      ["river", "Rivers"],
      ["island", "Islands"],
      ["forest", "Forests"],
      ["territory", "Sacred territories"],
      ["landmark", "Landmarks"]
    ];

    var groups = [];
    KINGDOMS.forEach(function (kg) {
      var g = { title: "The Kingdom of " + kg.n, meta: kg, sections: [] };
      SECTIONS.forEach(function (sec) {
        if (!catOk[sec[0]]) return;
        var rows = all.filter(function (p) {
          return p.k === kg.n && p.cat === sec[0] && p.n !== kg.n;
        });
        if (rows.length) g.sections.push({ label: sec[1], rows: rows });
      });
      groups.push(g);
    });
    var fe = { title: "The Far-Eastern Territories", meta: null, sections: [] };
    SECTIONS.forEach(function (sec) {
      if (!catOk[sec[0]]) return;
      var rows = all.filter(function (p) {
        return p.k === "the far-eastern territories" && p.cat === sec[0];
      });
      if (rows.length) fe.sections.push({ label: sec[1], rows: rows });
    });
    if (fe.sections.length) groups.push(fe);
    var neutral = { title: "Open Seas & Neutral Sites", meta: null, sections: [] };
    SECTIONS.forEach(function (sec) {
      if (!catOk[sec[0]]) return;
      var rows = all.filter(function (p) { return !p.k && p.cat === sec[0]; });
      if (rows.length) neutral.sections.push({ label: sec[1], rows: rows });
    });
    if (neutral.sections.length) groups.push(neutral);
    return { groups: groups, opts: opts };
  }

  function docTitle() { return texts.title || "Map of the World"; }
  function docSubtitle() { return texts.subtitle || "The Six Kingdoms — 7,250 BR"; }

  function buildHtmlDoc(data, mapDataUrl) {
    var h = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>" + esc(docTitle()) +
      "</title><style>body{font-family:Georgia,serif;max-width:900px;margin:30px auto;padding:0 20px;color:#2d2717;background:#f7f2e2}" +
      "h1{letter-spacing:2px}h2{border-bottom:2px solid #8c7c50;padding-bottom:4px;margin-top:38px}" +
      "h3{color:#6d5c32;margin:20px 0 6px}img{max-width:100%;border:1px solid #8c7c50}" +
      "li{margin:3px 0}em{color:#6d6142}.cap{font-style:italic;color:#6d6142}</style></head><body>";
    h += "<h1>" + esc(docTitle()) + "</h1><p class='cap'>" + esc(docSubtitle()) + "</p>";
    if (mapDataUrl) h += "<img src='" + mapDataUrl + "' alt='World map'>";
    data.groups.forEach(function (g) {
      h += "<h2>" + esc(g.title) + "</h2>";
      if (g.meta) {
        h += "<p>" + esc(g.meta.d) + " Capital: <b>" + esc(g.meta.capital) + "</b>.</p>";
        if (data.opts.biomes) {
          h += "<p><em>Principal biomes:</em> " + g.meta.biomes.map(esc).join(" · ") + "</p>";
        }
      }
      g.sections.forEach(function (sec) {
        h += "<h3>" + esc(sec.label) + "</h3><ul>";
        sec.rows.forEach(function (p) {
          h += "<li><b>" + esc(p.n) + "</b>" + (p.d ? " — " + esc(p.d) : "") + "</li>";
        });
        h += "</ul>";
      });
    });
    h += "<p class='cap'>Exported from the interactive atlas.</p></body></html>";
    return h;
  }

  function buildTextDoc(data, md) {
    var L = [];
    var H1 = md ? "# " : "", H2 = md ? "## " : "", H3 = md ? "### " : "";
    L.push(H1 + docTitle());
    L.push(docSubtitle());
    L.push("");
    data.groups.forEach(function (g) {
      L.push(H2 + g.title);
      if (!md) L.push("=".repeat(g.title.length));
      if (g.meta) {
        L.push(g.meta.d + " Capital: " + g.meta.capital + ".");
        if (data.opts.biomes) L.push("Principal biomes: " + g.meta.biomes.join(", ") + ".");
      }
      L.push("");
      g.sections.forEach(function (sec) {
        L.push(H3 + sec.label);
        sec.rows.forEach(function (p) {
          L.push((md ? "- **" + p.n + "**" : "* " + p.n) + (p.d ? " — " + p.d : ""));
        });
        L.push("");
      });
    });
    L.push(md ? "*Exported from the interactive atlas.*" : "Exported from the interactive atlas.");
    return L.join("\n");
  }

  function downloadFile(name, content, mime) {
    var blob = new Blob([content], { type: mime });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  document.getElementById("ex-go").addEventListener("click", function () {
    var fmt = document.getElementById("ex-format").value;
    if (fmt === "png" || fmt === "jpg") { exportViewImage(fmt); return; }
    var data = groupForDoc();
    if (fmt === "md") {
      downloadFile("map-of-the-world.md", buildTextDoc(data, true), "text/markdown");
    } else if (fmt === "txt") {
      downloadFile("map-of-the-world.txt", buildTextDoc(data, false), "text/plain");
    } else if (data.opts.mapimg) {
      fetch("assets/terrain.jpg").then(function (r) { return r.blob(); }).then(function (b) {
        var fr = new FileReader();
        fr.onload = function () {
          downloadFile("map-of-the-world.html", buildHtmlDoc(data, fr.result), "text/html");
        };
        fr.readAsDataURL(b);
      }).catch(function () {
        downloadFile("map-of-the-world.html", buildHtmlDoc(data, null), "text/html");
      });
    } else {
      downloadFile("map-of-the-world.html", buildHtmlDoc(data, null), "text/html");
    }
  });

  // ---------- boot ----------
  buildMarkers();
})();
