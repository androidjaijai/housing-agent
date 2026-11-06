#!/usr/bin/env bash
# Encrypt internal notes in notes/ (sales plans, pricing, report sources) into encrypted/notes.tar.gz.age.
# notes/ is git-ignored; only the encrypted archive is committed. Skips re-encrypting when notes/ is unchanged
# (hash kept in .git/, never committed); FORCE=1 re-encrypts anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -d notes ] || { echo "notes/ not found: run scripts/decrypt-notes.sh first." >&2; exit 1; }
[ -s keys/recipient.txt ] || { echo "keys/recipient.txt (public key) is missing." >&2; exit 1; }

mkdir -p encrypted
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00' -czf "$tmp" -C notes .

hash="$( (sha256sum "$tmp" 2>/dev/null || shasum -a 256 "$tmp") | cut -d' ' -f1)"
state=".git/hk-last-notes-hash"
if [ -f encrypted/notes.tar.gz.age ] && [ -f "$state" ] && [ "$(cat "$state")" = "$hash" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "notes unchanged; encrypted/notes.tar.gz.age left as is."
  exit 0
fi
age -R keys/recipient.txt < "$tmp" > encrypted/notes.tar.gz.age
(cd encrypted && (sha256sum notes.tar.gz.age 2>/dev/null || shasum -a 256 notes.tar.gz.age) > notes.tar.gz.age.sha256)
[ -d .git ] && echo "$hash" > "$state"
echo "Encrypted $(tar -tzf "$tmp" | grep -c -v '/$') files from notes/ into encrypted/notes.tar.gz.age"
