#!/usr/bin/env bash
# Stop hook: when the server has uncommitted changes, build it the way CI does
# (dotnet build -warnaserror) and send the errors back to Claude if it fails.
# Skips when nothing in server/ changed, when no .NET SDK is installed, and on
# the second stop in a row (stop_hook_active), so it never loops.

input=$(cat)
case "$input" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

[ -n "$(git status --porcelain -- server)" ] || exit 0
dotnet --list-sdks 2>/dev/null | grep -q '^10\.' || exit 0

if ! output=$(cd server && dotnet build -warnaserror -nologo -v q 2>&1); then
  {
    echo "dotnet build -warnaserror failed for server/ (CI would fail too). Fix these before finishing:"
    echo "$output" | grep -E ' error | warning ' | sort -u | head -40
  } >&2
  exit 2
fi
exit 0
