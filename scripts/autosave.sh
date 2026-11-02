#!/usr/bin/env bash
# Periodically encrypt, commit and push work in progress (useful during long sessions).
#   scripts/autosave.sh [interval-seconds] [iterations]     default: every 480s, 12 times
set -euo pipefail
cd "$(dirname "$0")/.."
interval="${1:-480}"
runs="${2:-12}"
branch="$(git rev-parse --abbrev-ref HEAD)"
for _ in $(seq 1 "$runs"); do
  sleep "$interval"
  # Encrypt first: app-src/ and src/ are git-ignored, so only the encrypted archives can change.
  [ -d app-src ] && scripts/encrypt-app.sh >/dev/null
  [ -d src ] && scripts/encrypt.sh >/dev/null
  git add encrypted docs scripts 2>/dev/null || true
  if ! git diff --cached --quiet; then
    git commit -q -m "WIP autosave $(TZ=Asia/Hong_Kong date '+%Y-%m-%d %H:%M') (encrypted)"
    git push -q origin "$branch" && echo "$(date '+%H:%M:%S') autosaved $(git log --oneline -1)"
  fi
done
