/* Bela — interactive atlas app */
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
      var q = { id: id, n: p.n, cat: p.cat, x: p.x, y: p.y, d: p.d };
      if (e) {
        ["n", "cat", "x", "y", "d"].forEach(function (k) {
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
    atlas: L.imageOverlay("assets/atlas.jpg", atlasBounds),
    height: L.imageOverlay("assets/height.jpg", atlasBounds),
    precipitation: L.imageOverlay("assets/precipitation.jpg", popBounds)
  };

  var currentBase = "atlas";
  layers.atlas.addTo(map);
  map.setMaxBounds([ll(-900, H + 700), ll(W + 900, -700)]);
  map.fitBounds(atlasBounds);

  // Prefetch the other layers so switching never shows a blank map
  window.addEventListener("load", function () {
    ["assets/height.jpg", "assets/precipitation.jpg"].forEach(function (src) {
      var im = new Image(); im.src = src;
    });
  });

  // ---------- categories ----------
  var CATS = [
    { id: "region", label: "Realms & regions", size: 13 },
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

  // ---------- marker construction ----------
  function viewPopupContent(p) {
    var div = document.createElement("div");
    var html = '<div class="popup-name">' + esc(p.n) + "</div>" +
      '<div class="popup-cat">' + esc(catLabel(p.cat)) + "</div>" +
      (p.d ? '<div class="popup-desc">' + esc(p.d) + "</div>" : "");
    div.innerHTML = html;
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
    var icon = L.divIcon({
      className: "dot dot-" + p.cat,
      iconSize: [size, size]
    });
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
      custom.push({
        id: "c" + Date.now(),
        n: vals.n, cat: vals.cat,
        x: Math.round(xy.x), y: Math.round(xy.y),
        d: vals.d
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
      this._div.innerHTML = mi + " mi" + '<div class="bar" style="width:' + px + 'px"></div>';
    }
  });
  map.addControl(new ScaleCtl());

  // ---------- boot ----------
  buildMarkers();
})();
