#!/usr/bin/env python3
"""Builds the counties: the land every town governs, its city plots and the countryside around them.

Run: python3 tools/build_counties.py   (after tools/build_cities.py and tools/build_countries.py; needs numpy)

A town's county grows from its city plots (as tools/build_cities.py gives them to towns) over the land of the
same country, a plot a step, until it meets another county, the sea or a border; so every plot of land goes
to the nearest town of its country by land. Land no town reaches (an island without a town) belongs to no
county. City plots no town is near (the server makes each a town of its own) are counties of their own on the
map and do not grow, and the server's file leaves them out: it asks the city for those.

Output:
- server/src/Modules/FactoryWorld.Modules.World/Data/counties.bin.gz: gzip of "FWK1", u16 width, u16 height
  (little endian), then a u16 per plot, row by row: 0 for none, i + 1 for the i-th town of cities.tsv.gz;
- client/world/counties.bin.gz: gzip of "FWK1", u16 width, u16 height, then one byte per plot whose bits say
  which of its sides is a county border (1 west, 2 east, 4 north, 8 south), for the map shader.
"""
import gzip
import struct

import numpy as np

from build_world import ROOT

SERVER = ROOT / "server/src/Modules/FactoryWorld.Modules.World/Data"


def main() -> None:
    raw = gzip.open(ROOT / "client/world/countries.bin.gz").read()
    assert raw[:4] == b"FWC1"
    width, height, count = struct.unpack("<HHH", raw[4:10])
    at = 10
    for _ in range(count):
        at = raw.index(b"\n", at) + 1
    country = np.frombuffer(raw[at:], np.uint8).reshape(height, width)

    lines = gzip.open(SERVER / "cities.tsv.gz", "rt", encoding="utf-8").read().splitlines()
    towns = int(lines[0])
    county = np.zeros((height, width), np.int32)
    for line in lines[1 + towns:]:
        x, y, town = map(int, line.split("\t"))
        county[y, x] = town + 1
    biomes = gzip.open(ROOT / "client/world/biomes.bin.gz").read()
    city = np.frombuffer(biomes[8:], np.uint8).reshape(height, width) == 9
    lone = city & (county == 0)
    county[lone] = towns + 1 + np.arange(lone.sum())

    # Grow every county a step at a time, alternating four and eight neighbours so they come out round-ish.
    # Columns wrap around the globe: the grid is padded with a copy of the last and first column.
    land = country > 0
    straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    padded_country = np.concatenate([country[:, -1:], country, country[:, :1]], axis=1)
    step = 0
    while True:
        grown = 0
        for dx, dy in straight + (diagonal if step % 2 else []):
            padded = np.concatenate([county[:, -1:], county, county[:, :1]], axis=1)
            # The neighbour at (x - dx, y - dy) of every plot (x, y) in rows that have one.
            rows = slice(max(dy, 0), height + min(dy, 0))
            source_rows = slice(max(-dy, 0), height + min(-dy, 0))
            source = padded[source_rows, 1 - dx:1 - dx + width]
            source_country = padded_country[source_rows, 1 - dx:1 - dx + width]
            here = county[rows]
            take = (here == 0) & land[rows] & (source > 0) & (source <= towns) & (source_country == country[rows])
            here[take] = source[take]
            grown += int(np.count_nonzero(take))
        step += 1
        if step % 50 == 0:
            print(f"step {step}: {grown:,} plots", flush=True)
        if grown == 0:
            break

    server = np.where(county <= towns, county, 0).astype("<u2")
    data = gzip.compress(b"FWK1" + struct.pack("<HH", width, height) + server.tobytes(), compresslevel=9, mtime=0)
    (SERVER / "counties.bin.gz").write_bytes(data)
    print(f"Wrote counties.bin.gz for the server ({len(data) / 1e6:.2f} MB, {step} steps,"
          f" {int((county > 0).sum()):,} of {int(land.sum()):,} plots of land in a county)")

    sides = np.zeros((height, width), np.uint8)
    for bit, (dx, dy) in enumerate([(-1, 0), (1, 0), (0, -1), (0, 1)]):
        other = np.roll(county, (-dy, -dx), axis=(0, 1))
        if dy < 0:
            other[0] = county[0]
        elif dy > 0:
            other[-1] = county[-1]
        # A border between two counties, or between a county and land outside any; not along the coast.
        border = (county != other) & (np.maximum(county, other) > 0) & land & np.roll(land, (-dy, -dx), axis=(0, 1))
        sides |= np.where(border, np.uint8(1 << bit), np.uint8(0))
    data = gzip.compress(b"FWK1" + struct.pack("<HH", width, height) + sides.tobytes(), compresslevel=9, mtime=0)
    (ROOT / "client/world/counties.bin.gz").write_bytes(data)
    print(f"Wrote client/world/counties.bin.gz ({len(data) / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
