#!/usr/bin/env python3
"""Builds the countries of the world map: which country every plot of land lies in.

Run: python3 tools/build_countries.py   (after tools/build_world.py; needs numpy and Pillow, downloads
Natural Earth's 1:10m countries once into tools/.world-cache/)

Borders are Natural Earth's (the de facto lines it draws by default). Pieces of land too small to
hold a few plots (Vatican, Monaco, leased bases, reefs) are left out, and plots the country outlines
miss along coasts are given to the nearest country. Antarctica, the sea and lakes belong to nobody.

Output (the same file goes to the server and the client):
- server/src/Modules/FactoryWorld.Modules.World/Data/countries.bin.gz
- client/world/countries.bin.gz: gzip of "FWC1", u16 width, u16 height, u16 count (little endian),
  then count lines "code, name, label column, label row, plots" (tab-separated, UTF-8): the code is
  Natural Earth's ADM0_A3, the name Polish, the label column and row the plot where the map writes the name,
  and plots the number of plots of land in the country;
  then one byte per plot, row by row: 0 for no country, i for the i-th country of the list.
  The codes go into the database, so a country keeps its code when the file is built again.
"""
import gzip
import struct

import numpy as np
from PIL import Image, ImageDraw

from build_world import HEIGHT, LAKE, OCEAN, ROOT, WIDTH, natural_earth, plot_centres, to_grid

# Countries smaller than this many plots are left out: their land goes to their neighbours.
MIN_PLOTS = 6
# Bases, buffer zones and disputed glaciers Natural Earth draws apart: their land goes to the country around them.
DROP = {"ATA", "ESB", "WSB", "KAB", "USG", "CNM", "BRT", "KAS", "SPI", "BRI", "PGA", "SCR", "BJN", "SER"}
# Plots along coasts the outlines miss: given to the nearest country within this many plots.
FILL_REACH = 25

# Natural Earth's Polish names that a player would not look for.
NAMES = {
    "TWN": "Tajwan",
    "PSX": "Palestyna",
    "SAH": "Sahara Zachodnia",
    "CYN": "Cypr Północny",
    "USA": "Stany Zjednoczone",
    "GBR": "Wielka Brytania",
    "CZE": "Czechy",
    "PRK": "Korea Północna",
    "KOR": "Korea Południowa",
    "COD": "Demokratyczna Republika Konga",
    "COG": "Kongo",
    "CAF": "Republika Środkowoafrykańska",
}


def rasterize_countries(features: list) -> np.ndarray:
    """Index of the country (into `features`, from 1) whose outline holds each plot's centre.
    Larger countries are drawn first, so an enclave (Lesotho, San Marino) is drawn over the hole in the one around it."""
    img = Image.new("I", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(img)
    for index, feature in enumerate(features, start=1):
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            for i, ring in enumerate(polygon):
                points = [to_grid(lon, lat) for lon, lat in ring]
                points = [(c - 0.5, r - 0.5) for c, r in points]
                if len(points) >= 3:
                    draw.polygon(points, fill=0 if i else index)
    return np.array(img, dtype=np.int32)


def area(feature: dict) -> float:
    """A rough size, to draw large countries first (in square degrees, which is enough to order them)."""
    geometry = feature["geometry"]
    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    total = 0.0
    for polygon in polygons:
        ring = np.array(polygon[0])
        x, y = ring[:, 0], ring[:, 1]
        total += abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1))) / 2
    return total


def fill_coasts(grid: np.ndarray, land: np.ndarray) -> None:
    """Gives land the outlines missed to the country next to it, a ring of plots at a time."""
    for _ in range(FILL_REACH):
        missing = land & (grid == 0)
        if not missing.any():
            return
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(grid, dx, axis=1)
            if dy:
                shifted = np.roll(shifted, dy, axis=0)
                shifted[0 if dy > 0 else -1, :] = 0
            take = missing & (grid == 0) & (shifted != 0)
            grid[take] = shifted[take]


def main() -> None:
    raw = gzip.open(ROOT / "client/world/biomes.bin.gz").read()
    assert raw[:4] == b"FWW1" and struct.unpack("<HH", raw[4:8]) == (WIDTH, HEIGHT)
    biomes = np.frombuffer(raw[8:], dtype=np.uint8).reshape(HEIGHT, WIDTH)
    _, lat = plot_centres()
    land = ~np.isin(biomes, [OCEAN, LAKE]) & (lat[:, None] > -60)

    features = [f for f in natural_earth("ne_10m_admin_0_countries")
                if f["geometry"] is not None and f["properties"]["ADM0_A3"] not in DROP]
    features.sort(key=lambda f: -area(f))

    print(f"Rasterizing {len(features)} countries")
    grid = rasterize_countries(features)
    grid[~land] = 0
    counts = np.bincount(grid.ravel(), minlength=len(features) + 1)
    small = [i for i in range(1, len(features) + 1) if counts[i] < MIN_PLOTS]
    grid[np.isin(grid, small)] = 0
    fill_coasts(grid, land)

    # Number the countries that are left by name, from 1.
    counts = np.bincount(grid.ravel(), minlength=len(features) + 1)
    kept = [i for i in range(1, len(features) + 1) if counts[i] > 0]

    def name(i: int) -> str:
        p = features[i - 1]["properties"]
        return NAMES.get(p["ADM0_A3"]) or p["NAME_PL"] or p["NAME"]

    kept.sort(key=name)
    assert len(kept) < 256
    renumber = np.zeros(len(features) + 1, dtype=np.uint8)
    for new, old in enumerate(kept, start=1):
        renumber[old] = new
    grid = renumber[grid]

    def line(i: int) -> str:
        p = features[i - 1]["properties"]
        col, row = to_grid(p["LABEL_X"], p["LABEL_Y"])
        return f"{p['ADM0_A3']}\t{name(i)}\t{int(col) % WIDTH}\t{int(row)}\t{counts[i]}\n"

    lines = "".join(line(i) for i in kept).encode("utf-8")
    codes = [features[i - 1]["properties"]["ADM0_A3"] for i in kept]
    assert len(set(codes)) == len(codes), "country codes repeat"
    data = gzip.compress(b"FWC1" + struct.pack("<HHH", WIDTH, HEIGHT, len(kept)) + lines + grid.tobytes(),
                         compresslevel=9, mtime=0)
    for path in (ROOT / "server/src/Modules/FactoryWorld.Modules.World/Data/countries.bin.gz",
                 ROOT / "client/world/countries.bin.gz"):
        path.write_bytes(data)
        print("Wrote", path.relative_to(ROOT), f"({len(data) / 1e6:.1f} MB)")
    print(f"  {len(kept)} countries, {np.count_nonzero(grid):,} plots of land in one, "
          f"{np.count_nonzero(land & (grid == 0)):,} in none")


if __name__ == "__main__":
    main()
