# Worldbuilding-WORLDWITHOUTGOD

A world building site that helps me think and process world building for my World Without God universe.

## Map of the World — Interactive Atlas

An interactive, explorable map of the six kingdoms as they stood in 7,250 BR,
rebuilt from the Azgaar Fantasy Map Generator exports as a self-contained
static website.

**🗺️ Live site: <https://isabelleereinhardt-rgb.github.io/Worldbuilding-WORLDWITHOUTGOD/>**

### Run it

No build step — it's plain HTML/JS/CSS. Serve the folder and open it:

```bash
python3 -m http.server 8000
# then visit http://localhost:8000
```

Or enable GitHub Pages for this repository (deploy from branch, root folder)
and it will be live at your Pages URL.


### Two eras (tabs)

The atlas has two switchable era tabs at the top of the sidebar:

- **Six Kingdoms Era** (~7,250 BR) — the original six-kingdoms political map.
- **Empire Era** (~7,160 BR – ~1,852 AR) — the Early Empire through the Golden
  Millennia: the Caporiolan Kingdom, Theolisseia, the Uxridian and Tanan Grand
  Duchies, Hikai and Lingia. Built from the Azgaar SVG export (names taken
  verbatim from the vector labels; countries assigned by point-in-polygon of
  the state borders).

Both eras share the same geography, so the heightmap, precipitation, ocean
(ship) routing and mile scale are common to both; each tab has its own
labeled base map, searchable markers with descriptions, distance tracker,
export, and read-aloud. Edits are saved per era.

Each tab carries the **same five map layers** — Terrain, Atlas, Heightmap,
Precipitation, and Kingdom borders. The Empire tab's Terrain, Atlas and
Kingdom-borders layers are rendered from its own Azgaar SVG export (so they
show the Empire-era states and labels), while the Heightmap and Precipitation
layers are shared with the Six Kingdoms tab, since the land itself is unchanged.

### Features

- **Pan & zoom** across the full 7680×3962 px atlas.
- **Four switchable layers**, aligned to one coordinate space:
  - *Terrain (default)* — full-opacity elevation render with all labels
  - *Atlas* — the labeled political/terrain map
  - *Heightmap* — unlabeled elevation render
  - *Precipitation* — rainfall map (blue dots mark how much rain each area gets)
- **Compare mode** — blend a second layer over the base with an opacity slider.
- **~425 searchable places** — the six kingdoms and their capitals, regions,
  cities & ports, towns, seas & lakes, rivers, islands, forests, sacred
  territories, and landmarks, each with a marker, tooltip and popup. Names and
  descriptions cross-checked against the world canon document; every place
  lists its kingdom and nearest neighbours. Town markers declutter
  automatically at low zoom.
- **Distance tracker** — pick any two places in the sidebar to get the
  straight-line distance in miles plus rough travel times on foot / mounted.
- **Document export** — build a gazetteer document from the map (like
  Azgaar's export settings): toggle the full map image, kingdoms & regions,
  cities & towns, seas/lakes/rivers, islands & forests, sacred territories &
  landmarks, and per-kingdom biomes; output as a web page, Markdown, or
  plain text.
- **Click anywhere** on any layer to see the nearest named place and its
  distance in miles.
- **Edit mode** — edit any place's name, category and description; drag
  markers to reposition them; click empty map to add new places; delete
  places; edit the site title and About text. Edits persist in your browser
  (localStorage) and can be exported as a ready-to-commit `places.js` with
  the *Download places.js* button.
- **Biome legend** extracted from the world's biome table.
- **Mile scale bar** calibrated from the map's own 600-mile scale bar
  (1 atlas pixel ≈ 0.8 mi).

### Layout

```
index.html        app shell
css/style.css     styling
js/app.js         Leaflet app logic
js/places.js      gazetteer data (place name, category, x/y in atlas pixels)
assets/           the three map layer images
vendor/leaflet/   Leaflet 1.9.4 (vendored; works offline)
```

### Editing places

Add or fix entries in `js/places.js`. Coordinates are pixels in the atlas
image (origin top-left). Categories: `region`, `city`, `town`, `water`,
`island`, `forest`, `territory`, `landmark`. An optional `d` field adds a
description shown in the marker popup.
