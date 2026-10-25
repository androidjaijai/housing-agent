#!/usr/bin/env bash
# Encrypt the plaintext site in src/ into encrypted/site.tar.gz.age using the public key(s) in keys/recipient.txt.
# Only holders of the matching private key can decrypt it (see scripts/decrypt.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v age >/dev/null || { echo "age is not installed: https://github.com/FiloSottile/age#installation" >&2; exit 1; }
[ -d src ] || { echo "src/ not found: decrypt first or create the source." >&2; exit 1; }
[ -s keys/recipient.txt ] || { echo "keys/recipient.txt (public key) is missing." >&2; exit 1; }

mkdir -p encrypted
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Deterministic-ish tarball: sorted names, fixed owner, no mtime noise from the host.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00' -czf "$tmp" -C src .
age -R keys/recipient.txt < "$tmp" > encrypted/site.tar.gz.age
sha256sum encrypted/site.tar.gz.age | tee encrypted/site.tar.gz.age.sha256
echo "Encrypted $(tar -tzf "$tmp" | grep -c -v '/$') files into encrypted/site.tar.gz.age"
