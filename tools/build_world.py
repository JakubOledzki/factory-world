#!/usr/bin/env python3
"""Builds the world map: the biome of every 5 × 5 km plot of the Earth and the towns shown on it.

Run: python3 tools/build_world.py   (needs numpy and Pillow; downloads ~120 MB of open data once
into tools/.world-cache/)

The plots form a grid in the Behrmann projection (cylindrical equal-area, true at 30° N/S, as
in EASE-Grid 2.0), so every plot covers 25 km² anywhere on the globe. Column 0 starts at 180° W,
row 0 is the North Pole. The grid is WIDTH × HEIGHT plots.

Where the biomes come from:
- climate zones (Köppen-Geiger, Rubel & Kottek, 100″ grid, via the kgcpy package): land and sea,
  deserts, steppes, tundra, ice caps, and which plots can be forest or farmland;
- Natural Earth 1:10m: urban areas (cities), lakes, glaciers and mountain ranges;
- forest versus farmland inside one climate zone has no free global map small enough to use
  here, so it is split by deterministic noise in proportions typical of the climate.

Outputs (the same biome file goes to the server and the client; a server test checks they match):
- server/src/Modules/FactoryWorld.Modules.World/Data/biomes.bin.gz
- client/world/biomes.bin.gz: gzip of "FWW1", u16 width, u16 height (little endian), then one
  byte per plot, row by row (biome ids below, same as World.Biome on the server);
- client/world/towns.tsv.gz: one town per line, "column, row, population, name", largest first;
  names from GeoNames (towns of 1000+ people), with Polish names from Natural Earth where it
  has them (Warszawa, Monachium, Pekin...).
"""
import gzip
import io
import json
import math
import struct
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(__file__).resolve().parent / ".world-cache"

RADIUS = 6371.0072  # km, authalic Earth radius
PLOT = 5.0  # km
COS = math.cos(math.radians(30))
WIDTH = round(2 * math.pi * RADIUS * COS / PLOT)  # 6933
HEIGHT = int(2 * RADIUS / COS / PLOT)  # 2942

OCEAN, LAKE, FOREST, FARMLAND, GRASSLAND, DESERT, MOUNTAINS, TUNDRA, ICE, CITY, COAST, LAKESHORE = range(12)

NATURAL_EARTH = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
KGCPY = "https://files.pythonhosted.org/packages/py3/k/kgcpy/kgcpy-1.1.8-py3-none-any.whl"
CITIES = "https://registry.npmjs.org/all-the-cities/-/all-the-cities-3.1.0.tgz"

# Köppen zone numbers of kgcpy (kg_zoneNum.csv).
KOPPEN = {name: i + 1 for i, name in enumerate(
    "Af Am As Aw BSh BSk BWh BWk Cfa Cfb Cfc Csa Csb Csc Cwa Cwb Cwc "
    "Dfa Dfb Dfc Dfd Dsa Dsb Dsc Dsd Dwa Dwb Dwc Dwd EF ET Ocean".split())}

# Share of forest, farmland and grassland in each climate whose plots are not desert, tundra or ice.
COVER = {
    "Af": (0.85, 0.15, 0.0), "Am": (0.7, 0.25, 0.05), "As": (0.25, 0.2, 0.55), "Aw": (0.25, 0.2, 0.55),
    "Cfa": (0.4, 0.5, 0.1), "Cfb": (0.4, 0.5, 0.1), "Cfc": (0.5, 0.0, 0.5),
    "Csa": (0.2, 0.5, 0.3), "Csb": (0.3, 0.45, 0.25), "Csc": (0.4, 0.2, 0.4),
    "Cwa": (0.3, 0.5, 0.2), "Cwb": (0.35, 0.4, 0.25), "Cwc": (0.4, 0.2, 0.4),
    "Dfa": (0.25, 0.6, 0.15), "Dsa": (0.2, 0.5, 0.3), "Dwa": (0.25, 0.6, 0.15),
    "Dfb": (0.5, 0.42, 0.08), "Dsb": (0.45, 0.3, 0.25), "Dwb": (0.5, 0.35, 0.15),
    "Dfc": (0.9, 0.02, 0.08), "Dfd": (0.9, 0.0, 0.1), "Dsc": (0.8, 0.0, 0.2), "Dsd": (0.8, 0.0, 0.2),
    "Dwc": (0.9, 0.0, 0.1), "Dwd": (0.9, 0.0, 0.1),
}


def fetch(url: str, name: str) -> Path:
    path = CACHE / name
    if not path.exists():
        print("Downloading", url)
        CACHE.mkdir(exist_ok=True)
        with urllib.request.urlopen(url) as response:
            path.write_bytes(response.read())
    return path


def natural_earth(layer: str) -> list:
    return json.loads(fetch(NATURAL_EARTH + layer + ".geojson", layer + ".geojson").read_text())["features"]


# --- Projection --------------------------------------------------------------------

def plot_centres() -> tuple[np.ndarray, np.ndarray]:
    """Longitude (columns) and latitude (rows) of plot centres, in degrees."""
    x = ((np.arange(WIDTH) + 0.5) * PLOT - WIDTH * PLOT / 2) / (RADIUS * COS)
    y = (HEIGHT * PLOT / 2 - (np.arange(HEIGHT) + 0.5) * PLOT) * COS / RADIUS
    lon = (np.degrees(x) + 180) % 360 - 180
    return lon, np.degrees(np.arcsin(np.clip(y, -1, 1)))


def to_grid(lon: float, lat: float) -> tuple[float, float]:
    """Continuous grid position (column, row) of a point; plot (c, r) spans [c, c+1) × [r, r+1)."""
    col = (math.radians(lon) * RADIUS * COS + WIDTH * PLOT / 2) / PLOT
    row = (HEIGHT * PLOT / 2 - RADIUS * math.sin(math.radians(lat)) / COS) / PLOT
    return col, row


def rasterize(features: list, keep=lambda props: True) -> np.ndarray:
    """True for every plot whose centre lies inside one of the (multi)polygons."""
    img = Image.new("L", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(img)
    for feature in features:
        if not keep(feature["properties"]) or feature["geometry"] is None:
            continue
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            for i, ring in enumerate(polygon):
                points = [to_grid(lon, lat) for lon, lat in ring]
                # PIL fills the pixels whose integer coordinates lie inside; shift to plot centres.
                points = [(c - 0.5, r - 0.5) for c, r in points]
                if len(points) >= 3:
                    draw.polygon(points, fill=0 if i else 1)
    return np.array(img, dtype=bool)


# --- Biomes ------------------------------------------------------------------------

def koppen_zones(lon: np.ndarray, lat: np.ndarray) -> np.ndarray:
    wheel = fetch(KGCPY, "kgcpy.whl")
    with zipfile.ZipFile(wheel) as z:
        Image.MAX_IMAGE_PIXELS = None
        source = np.array(Image.open(io.BytesIO(z.read("kgcpy/kmz_int_reshape.png"))))
    h, w = source.shape
    kx = np.clip(((lon + 180) / 360 * w).astype(int), 0, w - 1)
    ky = np.clip(((90 - lat) / 180 * h).astype(int), 0, h - 1)
    return source[np.ix_(ky, kx)]


def noise(seed: int) -> np.ndarray:
    """Smooth fractal noise over the grid, turned into a uniform 0..1 by rank."""
    rng = np.random.default_rng(seed)
    field = np.zeros((HEIGHT, WIDTH), dtype=np.float32)
    for cells, weight in ((24, 1.0), (12, 0.5), (6, 0.3), (3, 0.15)):
        small = rng.random((HEIGHT // cells + 2, WIDTH // cells + 2)).astype(np.float32)
        layer = Image.fromarray(small, mode="F").resize(
            ((WIDTH // cells + 2) * cells, (HEIGHT // cells + 2) * cells), Image.BICUBIC)
        field += weight * np.array(layer)[:HEIGHT, :WIDTH]
    order = field.ravel().argsort()
    ranks = np.empty(order.size, dtype=np.float32)
    ranks[order] = np.arange(order.size, dtype=np.float32) / order.size
    return ranks.reshape(field.shape)


def rugged(ranges: np.ndarray) -> np.ndarray:
    """Natural Earth draws mountain ranges as smooth outlines; noise gives them ragged edges and valleys."""
    blurred = Image.fromarray(ranges.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(8))
    return np.array(blurred, dtype=np.float32) / 255 + (noise(11) - 0.5) * 1.1 > 0.55


def near(mask: np.ndarray) -> np.ndarray:
    """Plots that touch `mask` (8 neighbours, wrapping east-west)."""
    out = mask.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            shifted = np.roll(mask, dx, axis=1)
            if dy:
                shifted = np.roll(shifted, dy, axis=0)
                shifted[0 if dy > 0 else -1, :] = False
            out |= shifted
    return out


def build_biomes() -> np.ndarray:
    lon, lat = plot_centres()
    print(f"Grid {WIDTH} × {HEIGHT} plots of {PLOT:g} × {PLOT:g} km")
    zones = koppen_zones(lon, lat)
    lat_grid = np.broadcast_to(lat[:, None], zones.shape)

    print("Rasterizing Natural Earth layers")
    lakes = rasterize(natural_earth("ne_10m_lakes"))
    urban = rasterize(natural_earth("ne_10m_urban_areas"))
    glaciers = rasterize(natural_earth("ne_10m_glaciated_areas"))
    ranges = rasterize(natural_earth("ne_10m_geography_regions_polys"),
                       lambda p: p["FEATURECLA"] == "Range/mtn")

    biomes = np.full(zones.shape, FARMLAND, dtype=np.uint8)
    u = noise(7)
    for zone, (forest, farmland, _) in COVER.items():
        here = zones == KOPPEN[zone]
        biomes[here & (u < forest)] = FOREST
        biomes[here & (u >= forest + farmland)] = GRASSLAND
    biomes[np.isin(zones, [KOPPEN["BWh"], KOPPEN["BWk"]])] = DESERT
    biomes[np.isin(zones, [KOPPEN["BSh"], KOPPEN["BSk"]])] = GRASSLAND
    alpine = (zones == KOPPEN["ET"]) & (np.abs(lat_grid) < 58)
    biomes[zones == KOPPEN["ET"]] = TUNDRA
    biomes[alpine | rugged(ranges)] = MOUNTAINS

    ocean = zones == KOPPEN["Ocean"]
    water = ocean | lakes
    biomes[near(lakes) & ~water] = LAKESHORE
    biomes[near(ocean) & ~water] = COAST
    biomes[urban & ~water] = CITY
    biomes[(zones == KOPPEN["EF"]) | (glaciers & ~water)] = ICE
    biomes[lakes & ~ocean] = LAKE
    biomes[ocean] = OCEAN
    return biomes


def write_biomes(biomes: np.ndarray) -> None:
    raw = b"FWW1" + struct.pack("<HH", WIDTH, HEIGHT) + biomes.tobytes()
    data = gzip.compress(raw, compresslevel=9, mtime=0)
    for path in (ROOT / "server/src/Modules/FactoryWorld.Modules.World/Data/biomes.bin.gz",
                 ROOT / "client/world/biomes.bin.gz"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print("Wrote", path.relative_to(ROOT), f"({len(data) / 1e6:.1f} MB)")
    counts = np.bincount(biomes.ravel(), minlength=12)
    for i, name in enumerate("ocean lake forest farmland grassland desert mountains tundra ice city coast lakeshore".split()):
        print(f"  {name:10} {counts[i]:>10,} plots")


# --- Towns -------------------------------------------------------------------------

def read_cities() -> list[dict]:
    """Decodes cities.pbf of the all-the-cities package (GeoNames, population ≥ 1000)."""
    import tarfile
    with tarfile.open(fetch(CITIES, "all-the-cities.tgz")) as tar:
        buf = tar.extractfile("package/cities.pbf").read()

    def varint(pos: int) -> tuple[int, int]:
        value = shift = 0
        while True:
            b = buf[pos]
            value |= (b & 0x7F) << shift
            pos += 1
            if b < 0x80:
                return value, pos
            shift += 7

    def zigzag(v: int) -> int:
        return (v >> 1) ^ -(v & 1)

    cities, pos, lon, lat = [], 0, 0, 0
    while pos < len(buf):
        length, pos = varint(pos)
        end = pos + length
        city = {"id": 0, "name": "", "population": 0}
        while pos < end:
            key, pos = varint(pos)
            tag, wire = key >> 3, key & 7
            if wire == 2:
                size, pos = varint(pos)
                value = buf[pos:pos + size].decode("utf-8")
                pos += size
                if tag == 2:
                    city["name"] = value
            else:
                value, pos = varint(pos)
                if tag == 1:
                    city["id"] = zigzag(value)
                elif tag == 9:
                    city["population"] = value
                elif tag == 10:
                    lon += zigzag(value)
                elif tag == 11:
                    lat += zigzag(value)
        city["lon"], city["lat"] = lon / 1e5, lat / 1e5
        cities.append(city)
    return cities


def write_towns(biomes: np.ndarray) -> None:
    polish = {}
    for f in natural_earth("ne_10m_populated_places"):
        p = f["properties"]
        if (p.get("GEONAMESID") or -1) > 0 and p.get("NAME_PL"):
            polish[p["GEONAMESID"]] = p["NAME_PL"]

    lines = []
    for city in sorted(read_cities(), key=lambda c: -c["population"]):
        col, row = to_grid(city["lon"], city["lat"])
        col, row = int(col) % WIDTH, min(max(int(row), 0), HEIGHT - 1)
        name = polish.get(city["id"], city["name"]).replace("\t", " ").strip()
        if name:
            lines.append(f"{col}\t{row}\t{city['population']}\t{name}")
    data = gzip.compress(("\n".join(lines) + "\n").encode("utf-8"), compresslevel=9, mtime=0)
    path = ROOT / "client/world/towns.tsv.gz"
    path.write_bytes(data)
    print("Wrote", path.relative_to(ROOT), f"({len(lines):,} towns, {len(data) / 1e6:.1f} MB)")


def main() -> None:
    biomes = build_biomes()
    write_biomes(biomes)
    write_towns(biomes)


if __name__ == "__main__":
    main()
