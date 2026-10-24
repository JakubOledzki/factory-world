#!/usr/bin/env bash
# Runs the load test for several numbers of players, one after another, and builds the report.
#
#   tools/loadtest/run.sh                                   # 10 100 1000 10000 players on ws://127.0.0.1:5080/ws
#   URL=wss://gra.example.com/ws LEVELS="10 100" tools/loadtest/run.sh
#   SERVER_PID=$(pgrep -f FactoryWorld.Server.dll) tools/loadtest/run.sh   # + CPU/RAM of the server (same machine)
#
# Settings (environment): URL, LEVELS, DURATION (s of play per level), THINK (ms between a player's actions),
# LOGIN (token|password), SERVER_PID, OUT (results folder).
set -euo pipefail
cd "$(dirname "$0")"

URL=${URL:-ws://127.0.0.1:5080/ws}
LEVELS=${LEVELS:-"10 100 1000 10000"}
DURATION=${DURATION:-60}
THINK=${THINK:-2000}
LOGIN=${LOGIN:-token}
OUT=${OUT:-results}
PID_ARG=()
if [[ -n "${SERVER_PID:-}" ]]; then PID_ARG=(--server-pid "$SERVER_PID"); fi

dotnet build -c Release -v quiet -nologo
BIN=bin/Release/net10.0/FactoryWorld.LoadTest.dll
mkdir -p "$OUT"
MAX=$(tr ' ' '\n' <<<"$LEVELS" | sort -n | tail -1)

# Bot accounts are registered once and reused (their tokens are kept in accounts.tsv).
dotnet "$BIN" --url "$URL" --players "$MAX" --prepare-only --accounts accounts.tsv

for n in $LEVELS; do
  # Players join over a ramp that grows with their number (at most 100 new players per second, at least 5 s).
  ramp=$(( n / 100 > 5 ? n / 100 : 5 ))
  echo "=== $n players (ramp ${ramp}s, play ${DURATION}s) ==="
  dotnet "$BIN" --url "$URL" --players "$n" --ramp "$ramp" --duration "$DURATION" --think "$THINK" \
    --login "$LOGIN" --accounts accounts.tsv --out "$OUT/$n.json" "${PID_ARG[@]}"
  sleep 5
done

python3 report.py "$OUT"/*.json > "$OUT/report.html"
echo "Report: $(pwd)/$OUT/report.html"
