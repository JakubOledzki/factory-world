#!/usr/bin/env python3
"""Builds the towns the server knows: which town every city plot belongs to.

Run: python3 tools/build_cities.py   (after tools/build_world.py; reads its outputs, needs nothing else)

A city plot belongs to the nearest town of 20 000 people or more within 10 plots (50 km); without one,
to the nearest town of any size within 10 plots, then within 30. Plots no town is near are left out,
and the server gives them a town of their own.

Output: server/src/Modules/FactoryWorld.Modules.World/Data/cities.tsv.gz, gzip of UTF-8 text:
- the number of towns N on the first line;
- N lines "column, row, population, name" (tab-separated), largest first; a town's index is its line;
- one line "column, row, town index" for every city plot that has a town.
"""
import gzip
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CITY = 9
CELL = 10


def main() -> None:
    raw = gzip.open(ROOT / "client/world/biomes.bin.gz").read()
    assert raw[:4] == b"FWW1"
    width, height = struct.unpack("<HH", raw[4:8])
    grid = raw[8:]
    plots = [(i % width, i // width) for i, b in enumerate(grid) if b == CITY]
    towns = []
    for line in gzip.open(ROOT / "client/world/towns.tsv.gz", "rt", encoding="utf-8").read().splitlines():
        col, row, population, name = line.split("\t")
        towns.append((int(col), int(row), int(population), name))

    def index(candidates):
        cells = defaultdict(list)
        for i in candidates:
            cells[(towns[i][0] // CELL, towns[i][1] // CELL)].append(i)
        return cells

    big = index([i for i, t in enumerate(towns) if t[2] >= 20000])
    every = index(range(len(towns)))

    def nearest(cells, x, y, reach):
        best = None
        span = reach // CELL + 1
        for cx in range(x // CELL - span, x // CELL + span + 1):
            for cy in range(y // CELL - span, y // CELL + span + 1):
                for i in cells.get((cx % (width // CELL + 1), cy), []):
                    dx = abs(towns[i][0] - x)
                    dx = min(dx, width - dx)
                    d = dx * dx + (towns[i][1] - y) ** 2
                    if d <= reach * reach and (best is None or d < best[0]):
                        best = (d, i)
        return best[1] if best else None

    owner = {}
    for x, y in plots:
        town = nearest(big, x, y, 10)
        if town is None:
            town = nearest(every, x, y, 10)
        if town is None:
            town = nearest(every, x, y, 30)
        if town is not None:
            owner[(x, y)] = town

    used = sorted(set(owner.values()))
    renumber = {old: new for new, old in enumerate(used)}
    lines = [str(len(used))]
    lines += [f"{towns[i][0]}\t{towns[i][1]}\t{towns[i][2]}\t{towns[i][3]}" for i in used]
    lines += [f"{x}\t{y}\t{renumber[t]}" for (x, y), t in sorted(owner.items(), key=lambda p: (p[0][1], p[0][0]))]
    data = gzip.compress(("\n".join(lines) + "\n").encode("utf-8"), compresslevel=9, mtime=0)
    path = ROOT / "server/src/Modules/FactoryWorld.Modules.World/Data/cities.tsv.gz"
    path.write_bytes(data)
    print("Wrote", path.relative_to(ROOT), f"({len(used):,} towns, {len(owner):,} of {len(plots):,} city plots, {len(data) / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
