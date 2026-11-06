#!/usr/bin/env bash
# Encrypt, commit and push in one step. Needed because app-src/ is git-ignored: without encrypting first there is
# nothing to stage, so a plain `git commit` stops before the pre-commit hook runs.
#   scripts/checkpoint.sh "commit message"
set -euo pipefail
cd "$(dirname "$0")/.."
msg="${1:?Usage: scripts/checkpoint.sh \"commit message\"}"
[ -d app-src ] && scripts/encrypt-app.sh
[ -d src ] && scripts/encrypt.sh >/dev/null
[ -d notes ] && scripts/encrypt-notes.sh >/dev/null
git add encrypted docs scripts README.md .gitignore keys 2>/dev/null || true
if git diff --cached --quiet; then echo "Nothing changed since the last checkpoint."; exit 0; fi
git commit -q -m "$msg"
git push -q origin "$(git rev-parse --abbrev-ref HEAD)"
git log --oneline -1
