# Worldbuilding-WORLDWITHOUTGOD

A world building site that helps me think and process world building for my World Without God universe.

## Bela Interactive Atlas

An interactive, explorable map of the world of **Bela**, rebuilt from the
Azgaar Fantasy Map Generator exports as a self-contained static website.

### Run it

No build step — it's plain HTML/JS/CSS. Serve the folder and open it:

```bash
python3 -m http.server 8000
# then visit http://localhost:8000
```

Or enable GitHub Pages for this repository (deploy from branch, root folder)
and it will be live at your Pages URL.

### Features

- **Pan & zoom** across the full 7680×3962 px atlas.
- **Three switchable layers**, aligned to one coordinate space:
  - *Atlas* — the labeled political/terrain map
  - *Heightmap* — elevation render
  - *Precipitation* — rainfall map (blue dots mark how much rain each area gets)
- **Compare mode** — blend a second layer over the base with an opacity slider.
- **~425 searchable places** — the six kingdoms and their capitals, regions,
  cities & ports, towns, seas & lakes, rivers, islands, forests, sacred
  territories, and landmarks, each with a marker, tooltip and popup. Names and
  descriptions cross-checked against the world canon document. Town markers
  declutter automatically at low zoom.
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
