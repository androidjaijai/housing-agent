#!/usr/bin/env bash
# Decrypt encrypted/site.tar.gz.age with your age private key and unpack the HTML site.
#   scripts/decrypt.sh path/to/private-key.txt [output-dir]   (default output-dir: site)
# Then open it with:  python3 -m http.server 8000 -d site   →  http://localhost:8000
set -euo pipefail
cd "$(dirname "$0")/.."

key="${1:-}"
out="${2:-site}"
[ -n "$key" ] && [ -f "$key" ] || { echo "Usage: scripts/decrypt.sh path/to/private-key.txt [output-dir]" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -f encrypted/site.tar.gz.age ] || { echo "encrypted/site.tar.gz.age not found." >&2; exit 1; }

if [ -f encrypted/site.tar.gz.age.sha256 ]; then
  sha256sum -c encrypted/site.tar.gz.age.sha256 >/dev/null || { echo "Checksum mismatch: the encrypted file was changed or corrupted." >&2; exit 1; }
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Stream to the temp file (works with every age version; some older ones mishandle -o on an existing file).
age -d -i "$key" encrypted/site.tar.gz.age > "$tmp"
if [ ! -s "$tmp" ] || ! gzip -t "$tmp" 2>/dev/null; then
  echo "Decryption produced no valid archive (age $(age --version 2>/dev/null || echo '?')). Check the key file and try: age -d -i \"$key\" encrypted/site.tar.gz.age | tar -tz | head" >&2
  exit 1
fi
rm -rf "$out"
mkdir -p "$out"
tar -xzf "$tmp" -C "$out"
echo "Decrypted to $out/"
echo "Run:  python3 -m http.server 8000 -d $out   then open http://localhost:8000"
