#!/usr/bin/env bash
# Encrypt the Laravel project in app-src/ into encrypted/laravel.tar.gz.age (public key: keys/recipient.txt).
# Excludes things that are rebuilt or secret: vendor/, node_modules/, .env, SQLite databases, caches, logs.
# Skips re-encrypting when the source has not changed since the last run (hash kept in .git/, never committed).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -d app-src ] || { echo "app-src/ not found: run scripts/decrypt-app.sh first." >&2; exit 1; }
[ -s keys/recipient.txt ] || { echo "keys/recipient.txt (public key) is missing." >&2; exit 1; }

mkdir -p encrypted
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00' \
  --exclude='./vendor' --exclude='./node_modules' --exclude='./.env' --exclude='./.env.backup' \
  --exclude='./database/*.sqlite' --exclude='./database/*.sqlite-journal' \
  --exclude='./storage/logs/*.log' --exclude='./storage/framework/cache/data/*' \
  --exclude='./storage/framework/sessions/*' --exclude='./storage/framework/views/*.php' \
  --exclude='./storage/app/public/*' --exclude='./public/storage' --exclude='./bootstrap/cache/*.php' \
  --exclude='./.phpunit.cache' --exclude='./.phpunit.result.cache' --exclude='./tests/Browser/screenshots' \
  -czf "$tmp" -C app-src .

hash="$(sha256sum "$tmp" | cut -d' ' -f1)"
state=".git/hk-last-app-hash"
if [ -f encrypted/laravel.tar.gz.age ] && [ -f "$state" ] && [ "$(cat "$state")" = "$hash" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "app-src unchanged; encrypted/laravel.tar.gz.age left as is."
  exit 0
fi
age -R keys/recipient.txt < "$tmp" > encrypted/laravel.tar.gz.age
sha256sum encrypted/laravel.tar.gz.age > encrypted/laravel.tar.gz.age.sha256
[ -d .git ] && echo "$hash" > "$state"
echo "Encrypted $(tar -tzf "$tmp" | grep -c -v '/$') files from app-src/ into encrypted/laravel.tar.gz.age"
