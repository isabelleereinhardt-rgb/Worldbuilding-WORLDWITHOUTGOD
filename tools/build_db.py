#!/usr/bin/env python3
"""
Extract text from all PDFs under source/, categorize, attach images,
build an entity index for cross-referencing, and emit site/data/db.json.
"""
import os, re, json, sys, hashlib
from pypdf import PdfReader

SRC = sys.argv[1]      # .../source
OUT = sys.argv[2]      # .../site/data/db.json

def slugify(s):
    s = re.sub(r"\.[A-Za-z0-9]+$", "", s)
    s = re.sub(r"[0-9a-f]{32}", "", s)
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or hashlib.md5(s.encode()).hexdigest()[:8]

def clean_text(t):
    t = t.replace("\x00", "")
    t = re.sub(r"[ \t]+\n", "\n", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    # de-hyphenate line breaks
    t = re.sub(r"(\w)-\n(\w)", r"\1\2", t)
    return t.strip()

def extract_pdf(path):
    try:
        r = PdfReader(path)
        if r.is_encrypted:
            try: r.decrypt("")
            except Exception: pass
        parts = []
        for pg in r.pages:
            try:
                parts.append(pg.extract_text() or "")
            except Exception:
                parts.append("")
        return clean_text("\n".join(parts))
    except Exception as e:
        return ""

# ---- categorization -------------------------------------------------
def categorize(folder, fname):
    n = fname.lower()
    if folder.startswith("canon"):
        return "Canon & Continuity"
    if folder.startswith("maps"):
        return "Maps & Locations"
    if folder == "religion":
        return "Religion & Faith"
    # core folder — decide by filename
    if n.startswith("house "):
        return "Noble Houses"
    if "noble house" in n:
        return "Noble Houses"
    if "character" in n or "historical_figures" in n or "three_sisters" in n:
        return "Characters"
    if "location" in n or n.startswith("map") or "map of the world" in n:
        return "Maps & Locations"
    if any(k in n for k in ["religion","the gods","the saints","nine-count","saints_attire"]):
        return "Religion & Faith"
    if "magic" in n:
        return "Magic System"
    if any(k in n for k in ["timeline","eras","name_evolution","name evolution"]):
        return "Timeline & History"
    if any(k in n for k in ["fashion","material_culture","jewelry","crest","funeral","flags","attire","nine-count","adornment"]):
        return "Culture & Fashion"
    if "book_info" in n or "tale_of" in n or "princess_in_love" in n or "crown_of_glory" in n:
        return "Books & Stories"
    if any(k in n for k in ["key_words","terms","quote","language"]):
        return "Reference & Lexicon"
    return "Reference & Lexicon"

def nice_title(fname, folder):
    t = re.sub(r"\.[A-Za-z0-9]+$", "", fname)
    t = re.sub(r"\s*[0-9a-f]{32}\s*", " ", t)
    t = re.sub(r"^[0-9a-f-]{30,}_?", "", t)
    t = t.replace("_", " ").replace("-", " ")
    t = re.sub(r"\s+", " ", t).strip()
    # Title case unless it has ALLCAPS meaning
    if t.isupper():
        t = t.title()
    return t or fname

IMG_EXT = (".png",".jpg",".jpeg",".gif",".webp")

# ---- walk source ----------------------------------------------------
entries = []       # text docs (pdfs)
image_files = []   # {folder, path, name}
for root, _, files in os.walk(SRC):
    rel = os.path.relpath(root, SRC)
    folder = "core" if rel == "." else rel.replace("\\","/")
    for f in sorted(files):
        p = os.path.join(root, f)
        relpath = os.path.relpath(p, SRC).replace("\\","/")
        low = f.lower()
        if low.endswith(".pdf"):
            text = extract_pdf(p)
            cat = categorize(folder, f)
            entries.append({
                "id": slugify(folder + "-" + f),
                "title": nice_title(f, folder),
                "category": cat,
                "folder": folder,
                "source": relpath,
                "type": "pdf",
                "text": text,
                "images": [],
            })
        elif low.endswith(IMG_EXT):
            image_files.append({"folder": folder, "path": relpath, "name": f})

# ---- image galleries: group images by folder into gallery entries ---
GALLERY_META = {
    "religion":   ("Religion — Visual Reference", "Religion & Faith"),
    "maps":       ("World Flags & Map Plates", "Maps & Locations"),
    "maps/solis": ("World Map: Solis", "Maps & Locations"),
    "maps/guide": ("General Map Guide — Regions", "Maps & Locations"),
}
by_folder = {}
for im in image_files:
    by_folder.setdefault(im["folder"], []).append(im["path"])

for folder, imgs in by_folder.items():
    if folder in GALLERY_META:
        title, cat = GALLERY_META[folder]
    elif folder == "core":
        continue  # no loose core images expected
    else:
        title, cat = (nice_title(folder, folder), "Maps & Locations")
    entries.append({
        "id": slugify("gallery-" + folder),
        "title": title,
        "category": cat,
        "folder": folder,
        "source": folder,
        "type": "gallery",
        "text": "",
        "images": sorted(imgs),
    })

# ---- entity index for cross-referencing -----------------------------
# House names from filenames
house_names = []
for e in entries:
    m = re.match(r"House\s+([A-Z][A-Za-z']+)", e["title"])
    if m:
        house_names.append(m.group(1))

# Gather candidate proper nouns from titles + a curated set
entity_terms = set()
for h in house_names:
    entity_terms.add("House " + h)
    entity_terms.add(h)

# Load English dictionary; coined/fantasy names are exactly the words NOT in it.
DICT = set()
dp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "words.txt")
if os.path.exists(dp):
    with open(dp) as fh:
        DICT = {w.strip().lower() for w in fh if w.strip()}

# Coined/fantasy names are single capitalized tokens NOT in the English dict.
# For cross-referencing, keep names that recur across >=2 documents (linkable).
freq = {}          # coined name -> set of doc ids
tokre = re.compile(r"\b([A-Z][a-zA-Z']{3,})\b")
# Real entities that ARE dictionary words but we still want linkable.
KEEP = {"Solis","Torad","Negiet","Coleum","Coelum","Academy"}
# Common Title-Case header words to always exclude even if not in dict.
HEADER_STOP = set("""Keywords References Weaknesses Vulnerabilities Relationships
Classification Distinguishing Achievements Reconstruction Representative
Traditionalist Individualistic Infrastructure Transformation Circumstances
Communication Enlightenment Reincarnation Sophisticated Unfortunately
Unsympathetic Worldbuilding Additionally Agricultural Consequences Continuation
Distribution Nationalist Description Significance Contradictory Unresolved
Establishments Chronological Northeast Northwest Southeast Southwest Northernmost
Southernmost Easternmost Westernmost Secondline Physical Special Historical
Founding Timeline Believers Population Fisherman Training Corruption Accounts
Questions Rivals Alliances Party Movement Empire Emperor Empress Princess Prince
Professor Hospital Detention Beautiful Creatures""".split())

for e in entries:
    for m in tokre.finditer(e["text"]):
        w = m.group(1)
        lw = w.lower()
        if w in HEADER_STOP: continue
        if (lw in DICT) and (w not in KEEP): continue
        if len(w) < 4: continue
        freq.setdefault(w, set()).add(e["id"])

EXTRA_STOP = set("""Backstory Overview Summary Section Chapter Appendix Contents
Notes Note Draft Final Version Update Status Facts Quick Info Theme Song Colors
Origin Founded Founder Seat Faction Wealth Military Religion Spirit Animal
Ation Tion Ically""".split())
titlecased = {w for w in freq if w[:1].isupper() and not w.isupper()}
for w, docs in freq.items():
    if len(docs) < 2: continue
    if w in EXTRA_STOP: continue
    if w.endswith("'s") or w.endswith("’s"): continue      # drop possessives
    if w.isupper() and w.title() in titlecased: continue    # drop ALLCAPS dup
    if len(w) < 4: continue
    entity_terms.add(w)

# Build final entity list, longest first for matching
entities = sorted(entity_terms, key=lambda s: (-len(s), s))

# ---- summaries (first meaningful paragraph) -------------------------
def make_summary(text, limit=320):
    if not text: return ""
    paras = [p.strip() for p in text.split("\n\n") if len(p.strip()) > 40]
    s = paras[0] if paras else text[:limit]
    s = re.sub(r"\s+", " ", s)
    return (s[:limit] + "…") if len(s) > limit else s

for e in entries:
    e["summary"] = make_summary(e["text"])
    e["wordcount"] = len(e["text"].split())

# category ordering
CAT_ORDER = ["Characters","Noble Houses","Maps & Locations","Religion & Faith",
             "Magic System","Timeline & History","Culture & Fashion",
             "Books & Stories","Reference & Lexicon","Canon & Continuity"]
def catkey(e):
    c = e["category"]
    return (CAT_ORDER.index(c) if c in CAT_ORDER else 99, e["title"].lower())
entries.sort(key=catkey)

cats = {}
for e in entries:
    cats.setdefault(e["category"], 0)
    cats[e["category"]] += 1

db = {
    "generated": True,
    "entries": entries,
    "entities": entities,
    "categories": [{"name": c, "count": cats[c]} for c in CAT_ORDER if c in cats],
    "stats": {
        "entries": len(entries),
        "pdfs": sum(1 for e in entries if e["type"]=="pdf"),
        "galleries": sum(1 for e in entries if e["type"]=="gallery"),
        "images": len(image_files),
        "entities": len(entities),
    },
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as fh:
    json.dump(db, fh, ensure_ascii=False, separators=(",",":"))
# also emit a JS-assignment version so the site loads without fetch/CORS (works on file://)
jsout = os.path.join(os.path.dirname(OUT), "db.js")
with open(jsout, "w") as fh:
    fh.write("window.WORLD_DB = ")
    json.dump(db, fh, ensure_ascii=False, separators=(",",":"))
    fh.write(";\n")

print("entries:", len(entries), "| entities:", len(entities), "| images:", len(image_files))
print("categories:", json.dumps(cats, indent=0))
empty = [e["source"] for e in entries if e["type"]=="pdf" and e["wordcount"] < 5]
print("empty/low-text PDFs:", len(empty))
for s in empty: print("  -", s)
