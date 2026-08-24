/* Map of the World — interactive atlas app */
(function () {
  "use strict";

  // Atlas image space (canonical coordinate system for all layers & markers).
  // Both era maps are Azgaar exports of the same world at the same scale, so
  // they share this coordinate space, the ocean grid, and the mile scale.
  var W = 7680, H = 3962;
  var MI_PER_PX = 0.7975; // from the map's 800-mile scale bar

  function ll(x, y) { return [H - y, x]; }
  function xyOf(latlng) { return { x: latlng.lng, y: H - latlng.lat }; }
  var atlasBounds = [ll(0, H), ll(W, 0)];
  // Precipitation export is the same viewport at a different zoom; these bounds
  // register it onto the atlas space (from landmass cross-correlation).
  var popBounds = [ll(63.7, 3956.7), ll(7675.2, 0)];

  // ---------- worlds (era tabs) ----------
  var WORLDS = {
    six: {
      id: "six", label: "Six Kingdoms Era",
      textDefaults: { title: "Map of the World", subtitle: "The Six Kingdoms \u2014 7,250 BR",
        about1: "A map of the six kingdoms of the world, as they stood in 7,250 BR." },
      places: (typeof PLACES !== "undefined") ? PLACES : [],
      states: (typeof KINGDOMS !== "undefined") ? KINGDOMS : [],
      defaultLayer: "terrain",
      layers: [
        { id: "terrain", label: "Terrain (default)", src: "assets/terrain.jpg", bounds: atlasBounds },
        { id: "atlas", label: "Atlas", src: "assets/atlas.jpg", bounds: atlasBounds },
        { id: "height", label: "Heightmap", src: "assets/height.jpg", bounds: atlasBounds },
        { id: "precipitation", label: "Precipitation", src: "assets/precipitation.jpg", bounds: popBounds },
        { id: "borders", label: "Kingdom borders", src: "assets/borders.jpg", bounds: atlasBounds }
      ]
    },
    empire: {
      id: "empire", label: "Empire Era",
      textDefaults: { title: "Map of the World", subtitle: "The Early Empire \u2192 the Golden Millennia",
        about1: "A map of the world from the Early Empire through the Golden Millennia \u2014 the age of the Caporiolan Kingdom, Theolisseia, the Uxridian and Tanan Grand Duchies, Hikai and Lingia (~7160 BR \u2013 ~1852 AR)." },
      places: (typeof PLACES_EMPIRE !== "undefined") ? PLACES_EMPIRE : [],
      states: (typeof EMPIRE_STATES !== "undefined") ? EMPIRE_STATES : [],
      defaultLayer: "terrain",
      layers: [
        { id: "terrain", label: "Terrain (default)", src: "assets/empire.jpg", bounds: atlasBounds }
      ]
    },
    present: {
      id: "present", label: "Present",
      textDefaults: { title: "Map of the World", subtitle: "The Present Age",
        about1: "A map of the world in the present age (~1,852 AR onward) — the six kingdoms of Lajazer, Civer, Atriki, Tarmet, Berlailia and Ociyaran, with the sacred island of the Cidet, the Academy and Thult in the west." },
      places: (typeof PLACES_PRESENT !== "undefined") ? PLACES_PRESENT : [],
      states: (typeof PRESENT_STATES !== "undefined") ? PRESENT_STATES : [],
      defaultLayer: "terrain",
      layers: [
        { id: "terrain", label: "Terrain (default)", src: "assets/present.jpg", bounds: atlasBounds }
      ]
    }
  };
  var active = WORLDS.six;
  function ensureLayerObjs(world) {
    if (world._objs) return;
    world._objs = {};
    world.layers.forEach(function (l) { world._objs[l.id] = L.imageOverlay(l.src, l.bounds); });
  }
  ensureLayerObjs(active);

  // ---------- per-world local edits (persisted in this browser) ----------
  function lsKey(kind) { return "bela." + kind + ".v1." + active.id; }
  function lsLoad(key, fallback) {
    try {
      var v = JSON.parse(localStorage.getItem(key));
      return v === null || v === undefined ? fallback : v;
    } catch (e) { return fallback; }
  }
  function lsSave(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {}
  }
  var edits, custom, texts;
  function loadEdits() {
    edits = lsLoad(lsKey("edits"), {});
    custom = lsLoad(lsKey("custom"), []);
    texts = lsLoad(lsKey("text"), {});
  }
  loadEdits();
  var editMode = false;

  // Merge base data + local edits into the working gazetteer
  function mergedPlaces() {
    var out = [];
    active.places.forEach(function (p, i) {
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

  var layers = active._objs;               // reassigned on world switch
  var currentBase = active.defaultLayer;
  layers[currentBase].addTo(map);
  map.setMaxBounds([ll(-900, H + 700), ll(W + 900, -700)]);
  map.fitBounds(atlasBounds);

  // Prefetch this world's other layers so switching never shows a blank map
  function prefetchLayers() {
    active.layers.forEach(function (l) { var im = new Image(); im.src = l.src; });
  }
  window.addEventListener("load", prefetchLayers);

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

  // ---------- duplicate-name disambiguation ----------
  // Two places can legitimately share a name (e.g. the two Anyes). Give each a
  // unique display label so the search list and distance pickers aren't ambiguous.
  function kingdomCapitalXY(k) {
    var cap = null;
    active.states.forEach(function (g) { if (g.n === k) cap = g.capital; });
    if (!cap) return null;
    var res = null;
    active.places.forEach(function (p) { if (p.n === cap) res = { x: p.x, y: p.y }; });
    return res;
  }
  function compassOf(dx, dy) {
    var ang = (Math.atan2(-dy, dx) * 180 / Math.PI + 360) % 360;
    var dirs = ["east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"];
    return dirs[Math.round(ang / 45) % 8];
  }
  function nameCountMap() {
    var c = {};
    mergedPlaces().forEach(function (p) { c[p.n] = (c[p.n] || 0) + 1; });
    return c;
  }
  function dispName(p, counts) {
    counts = counts || nameCountMap();
    if (counts[p.n] > 1) {
      var q;
      if (p.cat === "capital") {
        q = "capital";
      } else {
        var cap = kingdomCapitalXY(p.k);
        q = cap ? compassOf(p.x - cap.x, p.y - cap.y) : (p.k || "");
      }
      return p.n + " (" + q + ")";
    }
    return p.n;
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

  // ---------- base layer switching (dynamic per world) ----------
  var baseBox = document.getElementById("base-layers");
  var cmpOn = document.getElementById("cmp-on");
  var cmpSel = document.getElementById("cmp-layer");
  var cmpOpacity = document.getElementById("cmp-opacity");
  var cmpActive = null;

  function buildLayerControls() {
    // A single-layer era has nothing to switch or compare, so hide the panel.
    var layerPanel = baseBox.closest(".panel");
    if (layerPanel) layerPanel.style.display = active.layers.length > 1 ? "" : "none";
    baseBox.innerHTML = "";
    active.layers.forEach(function (l) {
      var lab = document.createElement("label");
      lab.className = "row";
      lab.innerHTML = '<input type="radio" name="base" value="' + l.id + '"' +
        (l.id === currentBase ? " checked" : "") + "> " + l.label;
      baseBox.appendChild(lab);
    });
    cmpSel.innerHTML = "";
    active.layers.forEach(function (l) {
      if (l.id === currentBase) return;
      var o = document.createElement("option");
      o.value = l.id; o.textContent = l.label;
      cmpSel.appendChild(o);
    });
  }
  baseBox.addEventListener("change", function (e) {
    if (e.target.name !== "base" || !e.target.checked) return;
    map.removeLayer(layers[currentBase]);
    currentBase = e.target.value;
    layers[currentBase].addTo(map);
    layers[currentBase].bringToBack();
    // refresh compare options so the current base isn't offered against itself
    var prev = cmpSel.value;
    buildLayerControls();
    if (prev && prev !== currentBase) cmpSel.value = prev;
    applyCompare();
  });

  function applyCompare() {
    if (cmpActive && map.hasLayer(cmpActive)) map.removeLayer(cmpActive);
    cmpActive = null;
    if (!cmpOn.checked) return;
    var key = cmpSel.value;
    if (!key || key === currentBase || !layers[key]) return;
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
    var counts = nameCountMap();
    var hits = mergedPlaces().filter(function (p) {
      return p.n.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 30);
    hits.forEach(function (p) {
      var li = document.createElement("li");
      li.innerHTML = "<span>" + esc(dispName(p, counts)) + '</span><span class="cat">' +
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

  function isVisiblePlace(p) {
    return enabled[p.cat] && !(p.cat === "town" && map.getZoom() < TOWN_MIN_ZOOM);
  }

  function showNearest(latlng) {
    var xy = xyOf(latlng);
    if (xy.x < -50 || xy.x > W + 50 || xy.y < -50 || xy.y > H + 50) return;
    // find the nearest currently-visible marker
    var best = null, bestD = Infinity;
    mergedPlaces().forEach(function (p) {
      if (!isVisiblePlace(p)) return;
      var dx = p.x - xy.x, dy = p.y - xy.y;
      var d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; best = p; }
    });
    if (!best) return;
    // only identify a place if the click landed near its marker on screen;
    // clicks in open space just pan/explore without a popup.
    var markPt = map.latLngToContainerPoint(ll(best.x, best.y));
    var clickPt = map.latLngToContainerPoint(latlng);
    if (markPt.distanceTo(clickPt) > 55) return;

    // show the place's own info, anchored on its marker (not the click point)
    var div = document.createElement("div");
    div.innerHTML = '<div class="popup-name">' + esc(best.n) + "</div>" +
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
    var mrow = document.createElement("div");
    mrow.className = "popup-measure";
    var startB = document.createElement("button");
    startB.className = "pbtn measure-btn";
    startB.textContent = "Measure ▸ start";
    startB.addEventListener("click", function () { setDistanceEndpoint("a", best); map.closePopup(); });
    var endB = document.createElement("button");
    endB.className = "pbtn measure-btn";
    endB.textContent = "▸ end";
    endB.addEventListener("click", function () { setDistanceEndpoint("b", best); map.closePopup(); });
    mrow.appendChild(startB); mrow.appendChild(endB);
    div.appendChild(mrow);
    L.popup().setLatLng(ll(best.x, best.y)).setContent(div).openOn(map);
  }

  // fill a distance-tracker endpoint from a clicked place and open the panel
  function setDistanceEndpoint(which, place) {
    var body = document.getElementById("dist-body");
    var head = document.querySelector('[data-target="dist-body"]');
    if (body && body.classList.contains("hidden")) {
      body.classList.remove("hidden");
      if (head) head.classList.add("open");
    }
    var input = document.getElementById(which === "a" ? "dist-a" : "dist-b");
    if (input) {
      input.value = dispName(place);
      if (typeof updateDistance === "function") updateDistance();
    }
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
      lsSave(lsKey("custom"), custom);
    } else {
      edits[id] = edits[id] || {};
      Object.keys(patch).forEach(function (k) { edits[id][k] = patch[k]; });
      lsSave(lsKey("edits"), edits);
    }
    buildMarkers();
  }

  function deletePlace(id) {
    if (id.charAt(0) === "c") {
      custom = custom.filter(function (p) { return p.id !== id; });
      lsSave(lsKey("custom"), custom);
    } else {
      edits[id] = edits[id] || {};
      edits[id].deleted = true;
      lsSave(lsKey("edits"), edits);
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
      active.places.forEach(function (q) {
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
      lsSave(lsKey("custom"), custom);
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
  function applyTexts() {
    editableEls.forEach(function (el) {
      var key = el.getAttribute("data-edit");
      var v = (texts && texts[key] !== undefined) ? texts[key]
        : (active.textDefaults ? active.textDefaults[key] : undefined);
      if (v !== undefined) el.textContent = v;
    });
  }
  editableEls.forEach(function (el) {
    var key = el.getAttribute("data-edit");
    el.addEventListener("input", function () {
      texts[key] = el.textContent;
      lsSave(lsKey("text"), texts);
    });
  });
  applyTexts();
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
      (active.id === "empire" ? "const PLACES_EMPIRE = [\n" : "const PLACES = [\n") + lines.join(",\n") + "\n];\n\n" +
      "const BIOMES = [\n" + biomes.join(",\n") + "\n];\n";
    var blob = new Blob([out], { type: "text/javascript" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = active.id === "empire" ? "places_empire.js" : "places.js";
    a.click();
    URL.revokeObjectURL(a.href);
  });

  document.getElementById("reset-btn").addEventListener("click", function () {
    if (!confirm("Discard ALL local edits (places and text) and restore the original data?")) return;
    localStorage.removeItem(lsKey("edits"));
    localStorage.removeItem(lsKey("custom"));
    localStorage.removeItem(lsKey("text"));
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


  // ---------- sea routing ----------
  var SEA = (typeof SEA_GRID !== "undefined") ? (function () {
    var raw = atob(SEA_GRID.bits);
    var bytes = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    var gw = SEA_GRID.gw, gh = SEA_GRID.gh, cell = SEA_GRID.cell;
    function nav(i, j) {
      if (i < 0 || j < 0 || i >= gw || j >= gh) return false;
      var idx = j * gw + i;
      return (bytes[idx >> 3] & (128 >> (idx & 7))) !== 0;
    }
    var COAST_CELLS = 3; // ~76 mi max from shore to still count as reachable
    // nearest navigable cell to atlas (x,y); returns {i,j,mi} or null
    function embark(x, y) {
      var ci = Math.floor(x / cell), cj = Math.floor(y / cell);
      var best = null, bd = 1e9;
      for (var dj = -COAST_CELLS; dj <= COAST_CELLS; dj++) {
        for (var di = -COAST_CELLS; di <= COAST_CELLS; di++) {
          if (nav(ci + di, cj + dj)) {
            var d = di * di + dj * dj;
            if (d < bd) { bd = d; best = { i: ci + di, j: cj + dj }; }
          }
        }
      }
      if (!best) return null;
      best.mi = Math.sqrt(bd) * cell * MI_PER_PX;
      return best;
    }
    // Dijkstra sea distance (mi) between two embark cells, 8-connected
    function route(ea, eb) {
      var key = function (i, j) { return j * gw + i; };
      var dist = {}, sk = key(ea.i, ea.j), tk = key(eb.i, eb.j);
      dist[sk] = 0;
      var pq = [[0, ea.i, ea.j]];
      function push(d, i, j) {
        pq.push([d, i, j]);
        var c = pq.length - 1;
        while (c > 0) { var pI = (c - 1) >> 1; if (pq[pI][0] <= pq[c][0]) break; var t = pq[pI]; pq[pI] = pq[c]; pq[c] = t; c = pI; }
      }
      function pop() {
        var top = pq[0], last = pq.pop();
        if (pq.length) { pq[0] = last; var c = 0; for (;;) { var l = 2 * c + 1, r = l + 1, m = c; if (l < pq.length && pq[l][0] < pq[m][0]) m = l; if (r < pq.length && pq[r][0] < pq[m][0]) m = r; if (m === c) break; var t = pq[m]; pq[m] = pq[c]; pq[c] = t; c = m; } }
        return top;
      }
      var SQ2 = Math.SQRT2, cellMi = cell * MI_PER_PX;
      while (pq.length) {
        var cur = pop(), d = cur[0], i = cur[1], j = cur[2], k = key(i, j);
        if (d > (dist[k] === undefined ? 1e18 : dist[k])) continue;
        if (k === tk) return d * cellMi;
        for (var dj = -1; dj <= 1; dj++) for (var di = -1; di <= 1; di++) {
          if (!di && !dj) continue;
          if (!nav(i + di, j + dj)) continue;
          var nk = key(i + di, j + dj), nd = d + (di && dj ? SQ2 : 1);
          if (nd < (dist[nk] === undefined ? 1e18 : dist[nk])) { dist[nk] = nd; push(nd, i + di, j + dj); }
        }
      }
      return null;
    }
    return {
      // returns {viable, embarkMi, seaMi} — seaMi filled only when routing both
      reachable: function (p) {
        if (p.cat === "island") return { viable: true, e: embark(p.x, p.y) };
        var e = embark(p.x, p.y);
        var isPort = /(^|\s)Port(\s|$)/.test(p.n);
        if (e && (e.mi <= 60 || isPort)) return { viable: true, e: e };
        return { viable: false, e: e };
      },
      route: route
    };
  })() : null;

  // ---------- distance tracker ----------
  var distList = document.getElementById("place-list");
  var distA = document.getElementById("dist-a");
  var distB = document.getElementById("dist-b");
  var distOut = document.getElementById("dist-result");

  function refreshDatalist() {
    distList.innerHTML = "";
    var counts = nameCountMap();
    mergedPlaces().slice().sort(function (a, b) { return a.n.localeCompare(b.n); })
      .forEach(function (p) {
        var o = document.createElement("option");
        o.value = dispName(p, counts);
        distList.appendChild(o);
      });
  }

  function findPlace(name) {
    var t = name.trim().toLowerCase();
    if (!t) return null;
    var all = mergedPlaces();
    var counts = nameCountMap();
    var i;
    // exact disambiguated label (e.g. "Anye (southeast)")
    for (i = 0; i < all.length; i++) {
      if (dispName(all[i], counts).toLowerCase() === t) return all[i];
    }
    // exact plain name — return first match
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

  function seaLine(pa, pb) {
    if (!SEA) return "";
    var ra = SEA.reachable(pa), rb = SEA.reachable(pb);
    if (!ra.viable || !rb.viable) {
      var who = [];
      if (!ra.viable) who.push(esc(dispName(pa)));
      if (!rb.viable) who.push(esc(dispName(pb)));
      return '<br><span class="sea-no">⚓ Not reachable by ship &mdash; ' +
        who.join(" and ") + (who.length > 1 ? " are landlocked." : " is landlocked.") + "</span>";
    }
    var seaMi = SEA.route(ra.e, rb.e);
    if (seaMi === null) {
      return '<br><span class="sea-no">⚓ No sea route found between these coasts.</span>';
    }
    var total = Math.round(seaMi + ra.e.mi + rb.e.mi);
    var days = Math.max(1, Math.round(total / 120)); // ~120 mi/day under sail
    return '<br><span class="sea-yes">⚓ By sea: <b>~' + total + " miles</b>, roughly <b>" +
      days + " day" + (days > 1 ? "s" : "") + "</b> by ship.</span>";
  }

  function updateDistance() {
    var a = sideStatus(distA), b = sideStatus(distB);
    if (a.state === "empty" && b.state === "empty") {
      distOut.innerHTML = "";
      return;
    }
    if (a.state === "ok" && b.state === "ok") {
      var pa = a.place, pb = b.place;
      if (pa.id === pb.id || (pa.x === pb.x && pa.y === pb.y)) {
        distOut.innerHTML = "Pick two different places.";
        return;
      }
      var mi = Math.round(Math.hypot(pa.x - pb.x, pa.y - pb.y) * MI_PER_PX);
      var foot = Math.max(1, Math.round(mi / 24));
      var horse = Math.max(1, Math.round(mi / 45));
      var html = "<b>" + esc(dispName(pa)) + "</b> &rarr; <b>" + esc(dispName(pb)) + "</b><br>" +
        '<span class="dist-big">~' + mi + " miles</span> as the crow flies<br>" +
        "Overland: roughly <b>" + foot + " day" + (foot > 1 ? "s" : "") + "</b> on foot or <b>" +
        horse + " day" + (horse > 1 ? "s" : "") + "</b> mounted.";
      html += seaLine(pa, pb);
      distOut.innerHTML = html;
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
  function layerInfo(key) {
    var l = null;
    active.layers.forEach(function (x) { if (x.id === key) l = x; });
    if (!l) return null;
    var lats = [l.bounds[0][0], l.bounds[1][0]], lngs = [l.bounds[0][1], l.bounds[1][1]];
    return {
      src: l.src,
      x0: Math.min(lngs[0], lngs[1]), x1: Math.max(lngs[0], lngs[1]),
      y0: H - Math.max(lats[0], lats[1]), y1: H - Math.min(lats[0], lats[1])
    };
  }
  var imgCache = {};
  function loadLayerImage(key) {
    return new Promise(function (resolve, reject) {
      var src = layerInfo(key).src;
      if (imgCache[src] && imgCache[src].complete) return resolve(imgCache[src]);
      var im = new Image();
      im.onload = function () { resolve(im); };
      im.onerror = reject;
      im.src = src;
      imgCache[src] = im;
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
        var inf = layerInfo(key);
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
    active.states.forEach(function (kg) {
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

  // ---------- world (era tab) switching ----------
  function switchWorld(id) {
    if (!WORLDS[id] || id === active.id) return;
    if (speechOK) window.speechSynthesis.cancel();
    map.closePopup();
    if (cmpActive && map.hasLayer(cmpActive)) map.removeLayer(cmpActive);
    cmpActive = null; cmpOn.checked = false;
    map.removeLayer(layers[currentBase]);
    // turn off edit mode when leaving a world
    if (editMode) { editMode = false; editToggle.checked = false; document.body.classList.remove("editing"); setTextEditable(false); }

    active = WORLDS[id];
    ensureLayerObjs(active);
    layers = active._objs;
    currentBase = active.defaultLayer;
    loadEdits();

    layers[currentBase].addTo(map);
    layers[currentBase].bringToBack();
    buildLayerControls();
    applyTexts();
    buildMarkers();
    renderResults("");
    distA.value = ""; distB.value = ""; distOut.innerHTML = "";
    prefetchLayers();

    document.querySelectorAll(".era-tab").forEach(function (t) {
      t.classList.toggle("active", t.getAttribute("data-world") === id);
    });
    map.fitBounds(atlasBounds);
  }
  document.querySelectorAll(".era-tab").forEach(function (t) {
    t.addEventListener("click", function () { switchWorld(t.getAttribute("data-world")); });
  });

  // ---------- boot ----------
  buildLayerControls();
  buildMarkers();
})();
