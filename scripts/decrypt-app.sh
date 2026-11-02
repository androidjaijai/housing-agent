#!/usr/bin/env bash
# Decrypt encrypted/laravel.tar.gz.age into app-src/ (or another folder) and print setup steps.
#   scripts/decrypt-app.sh path/to/private-key.txt [output-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

key="${1:-}"
out="${2:-app-src}"
[ -n "$key" ] && [ -f "$key" ] || { echo "Usage: scripts/decrypt-app.sh path/to/private-key.txt [output-dir]" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -f encrypted/laravel.tar.gz.age ] || { echo "encrypted/laravel.tar.gz.age not found." >&2; exit 1; }
if [ -f encrypted/laravel.tar.gz.age.sha256 ]; then
  sha256sum -c encrypted/laravel.tar.gz.age.sha256 >/dev/null || { echo "Checksum mismatch: the encrypted file was changed or corrupted." >&2; exit 1; }
fi
if [ -d "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "$out/ already exists and is not empty. Re-run with FORCE=1 to overwrite it (vendor/ and .env are kept)." >&2; exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
age -d -i "$key" encrypted/laravel.tar.gz.age > "$tmp"
if [ ! -s "$tmp" ] || ! gzip -t "$tmp" 2>/dev/null; then
  echo "Decryption produced no valid archive. Check the key file." >&2; exit 1
fi
mkdir -p "$out"
tar -xzf "$tmp" -C "$out"
echo "Decrypted Laravel project to $out/"
cat <<EOF
Next steps:
  cd $out
  composer install
  cp -n .env.example .env && php artisan key:generate
  touch database/database.sqlite && php artisan migrate --seed
  php artisan storage:link
  php artisan serve        # http://127.0.0.1:8000   admin: /admin  (see README for the demo login)
EOF
