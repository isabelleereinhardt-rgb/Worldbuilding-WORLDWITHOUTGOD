/* Bela — interactive atlas app */
(function () {
  "use strict";

  // Atlas image space (canonical coordinate system for all layers & markers)
  var W = 7680, H = 3962;
  var MI_PER_PX = 0.7975; // from the map's 600-mile scale bar

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

  var atlasBounds = [ll(0, H), ll(W, 0)]; // [[0,0],[H,W]]
  // Population export shows the same viewport rendered full-bleed at a
  // different zoom; bounds below register it onto the atlas space
  // (alignment computed by cross-correlating landmass silhouettes).
  var popBounds = [ll(63.7, 3956.7), ll(7675.2, 0)];

  var layers = {
    atlas: L.imageOverlay("assets/atlas.jpg", atlasBounds),
    height: L.imageOverlay("assets/height.jpg", atlasBounds),
    population: L.imageOverlay("assets/population.jpg", popBounds)
  };

  var currentBase = "atlas";
  layers.atlas.addTo(map);
  map.setMaxBounds([ll(-900, H + 700), ll(W + 900, -700)]);
  map.fitBounds(atlasBounds);

  // ---------- categories ----------
  var CATS = [
    { id: "region", label: "Realms & regions", size: 13 },
    { id: "city", label: "Cities & ports", size: 11 },
    { id: "town", label: "Towns & villages", size: 7 },
    { id: "water", label: "Seas & lakes", size: 10 },
    { id: "island", label: "Islands", size: 10 },
    { id: "forest", label: "Forests", size: 10 },
    { id: "territory", label: "Sacred territories", size: 9 },
    { id: "landmark", label: "Landmarks", size: 9 }
  ];
  var TOWN_MIN_ZOOM = -0.75; // towns unclutter at low zoom

  var groups = {};   // cat id -> layerGroup
  var enabled = {};  // cat id -> checkbox state
  var markers = [];  // { place, marker, cat }

  function makeMarker(p, size) {
    var icon = L.divIcon({
      className: "dot dot-" + p.cat,
      iconSize: [size, size]
    });
    var m = L.marker(ll(p.x, p.y), { icon: icon, title: p.n });
    var html = '<div class="popup-name">' + p.n + "</div>" +
      '<div class="popup-cat">' + catLabel(p.cat) + "</div>" +
      (p.d ? '<div class="popup-desc">' + p.d + "</div>" : "");
    m.bindPopup(html);
    m.bindTooltip(p.n, { className: "place-tip", direction: "top", offset: [0, -6] });
    return m;
  }

  function catLabel(id) {
    for (var i = 0; i < CATS.length; i++) if (CATS[i].id === id) return CATS[i].label;
    return id;
  }

  CATS.forEach(function (c) {
    groups[c.id] = L.layerGroup();
    enabled[c.id] = true;
  });

  PLACES.forEach(function (p) {
    var cat = null;
    for (var i = 0; i < CATS.length; i++) if (CATS[i].id === p.cat) cat = CATS[i];
    if (!cat) return;
    var m = makeMarker(p, cat.size);
    m.addTo(groups[p.cat]);
    markers.push({ place: p, marker: m, cat: p.cat });
  });

  function refreshGroups() {
    CATS.forEach(function (c) {
      var show = enabled[c.id] &&
        !(c.id === "town" && map.getZoom() < TOWN_MIN_ZOOM);
      if (show && !map.hasLayer(groups[c.id])) map.addLayer(groups[c.id]);
      if (!show && map.hasLayer(groups[c.id])) map.removeLayer(groups[c.id]);
    });
  }
  map.on("zoomend", refreshGroups);
  refreshGroups();

  // ---------- category toggle UI ----------
  var catBox = document.getElementById("cat-toggles");
  CATS.forEach(function (c) {
    var n = 0;
    PLACES.forEach(function (p) { if (p.cat === c.id) n++; });
    var lab = document.createElement("label");
    lab.innerHTML = '<input type="checkbox" checked data-cat="' + c.id + '">' +
      '<span class="swatch dot-' + c.id + '"></span>' + c.label +
      '<span class="count">' + n + "</span>";
    catBox.appendChild(lab);
  });
  catBox.addEventListener("change", function (e) {
    var cat = e.target.getAttribute("data-cat");
    if (!cat) return;
    enabled[cat] = e.target.checked;
    refreshGroups();
  });

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
    var hits = PLACES.filter(function (p) {
      return p.n.toLowerCase().indexOf(q) !== -1;
    }).slice(0, 30);
    hits.forEach(function (p) {
      var li = document.createElement("li");
      li.innerHTML = "<span>" + p.n + '</span><span class="cat">' +
        catLabel(p.cat) + "</span>";
      li.addEventListener("click", function () { goTo(p); });
      resultsList.appendChild(li);
    });
  }
  searchInput.addEventListener("input", function () { renderResults(this.value.trim()); });

  function goTo(p) {
    var z = p.cat === "town" ? 0.5 : Math.max(map.getZoom(), -0.5);
    map.flyTo(ll(p.x, p.y), z, { duration: 0.9 });
    var rec = null;
    markers.forEach(function (r) { if (r.place === p) rec = r; });
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

  // ---------- biome legend ----------
  var legend = document.getElementById("biome-legend");
  BIOMES.forEach(function (b) {
    var li = document.createElement("li");
    li.innerHTML = '<span class="bs" style="background:' + b.color + '"></span>' + b.name;
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
})();
