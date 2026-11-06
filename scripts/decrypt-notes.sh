#!/usr/bin/env bash
# Decrypt encrypted/notes.tar.gz.age (internal sales plans, pricing, report sources) into notes/.
#   scripts/decrypt-notes.sh path/to/private-key.txt [output-dir]   (default output-dir: notes)
# notes/pages/*.html open directly in a browser.
set -euo pipefail
cd "$(dirname "$0")/.."

key="${1:-}"
out="${2:-notes}"
[ -n "$key" ] && [ -f "$key" ] || { echo "Usage: scripts/decrypt-notes.sh path/to/private-key.txt [output-dir]" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -f encrypted/notes.tar.gz.age ] || { echo "encrypted/notes.tar.gz.age not found." >&2; exit 1; }

if [ -f encrypted/notes.tar.gz.age.sha256 ]; then
  (cd encrypted && (sha256sum -c notes.tar.gz.age.sha256 2>/dev/null || shasum -a 256 -c notes.tar.gz.age.sha256) >/dev/null) \
    || { echo "Checksum mismatch: the encrypted file was changed or corrupted." >&2; exit 1; }
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
age -d -i "$key" encrypted/notes.tar.gz.age > "$tmp"
if [ ! -s "$tmp" ] || ! gzip -t "$tmp" 2>/dev/null; then
  echo "Decryption produced no valid archive. Check the key file." >&2
  exit 1
fi
if [ -d "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "$out/ is not empty; set FORCE=1 to overwrite it." >&2
  exit 1
fi
rm -rf "$out"
mkdir -p "$out"
tar -xzf "$tmp" -C "$out"
echo "Decrypted to $out/  (sales/*.md, pages/*.html)"
