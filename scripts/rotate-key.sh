#!/usr/bin/env bash
# Rotate the age key: re-encrypt every encrypted archive on the given branches to a NEW public key.
#
#   scripts/rotate-key.sh OLD_PRIVATE_KEY NEW_PRIVATE_KEY [--no-push] [branch ...]
#
# Default branches: claude/v1-student claude/interactive-demo claude/phase8-opalstack
# For each branch: decrypt app (laravel), static demo (site) and notes with the OLD key, write the NEW public key to
# keys/recipient.txt, re-encrypt, check the NEW key decrypts to identical files, commit, and push (unless --no-push).
# Release branches (claude/release/*) are frozen snapshots and are left alone: keep the old key offline to open them.
#
# Generate the new key on your own machine first:
#   age-keygen -o ~/keys/housing-agent-key-NEW.txt && chmod 600 ~/keys/housing-agent-key-NEW.txt
# Keys may live in the repo's keys/ folder (git-ignored except recipient.txt) or anywhere outside the repo.
# A key inside the repo that git would track is refused.
set -euo pipefail
cd "$(dirname "$0")/.."

old="${1:-}"; new="${2:-}"
[ -n "$old" ] && [ -n "$new" ] || { echo "Usage: scripts/rotate-key.sh OLD_PRIVATE_KEY NEW_PRIVATE_KEY [--no-push] [branch ...]" >&2; exit 1; }
[ -f "$old" ] || { echo "OLD private key not found: $old" >&2; exit 1; }
[ -f "$new" ] || { echo "NEW private key not found: $new" >&2; exit 1; }
shift 2
push=1
branches=()
for arg in "$@"; do
  if [ "$arg" = "--no-push" ]; then push=0; else branches+=("$arg"); fi
done
[ ${#branches[@]} -gt 0 ] || branches=(claude/v1-student claude/interactive-demo claude/phase8-opalstack)

command -v age >/dev/null && command -v age-keygen >/dev/null || { echo "age / age-keygen not installed." >&2; exit 1; }
root="$(pwd)"
# A key inside the repository is allowed only when git ignores it and it is not tracked (e.g. keys/<name>.txt).
key_unsafe_in_repo() {
  local abs; abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  case "$abs" in "$root"/*) ;; *) return 1 ;; esac
  local rel="${abs#"$root"/}"
  git ls-files --error-unmatch "$rel" >/dev/null 2>&1 && return 0
  git check-ignore -q "$rel" && return 1
  return 0
}
key_unsafe_in_repo "$old" && { echo "The OLD key is inside the repository and not git-ignored. Put it in keys/ or outside the repo." >&2; exit 1; }
key_unsafe_in_repo "$new" && { echo "The NEW key is inside the repository and not git-ignored. Put it in keys/ or outside the repo." >&2; exit 1; }
newpub="$(age-keygen -y "$new")"
oldpub="$(age-keygen -y "$old")"
[ "$newpub" != "$oldpub" ] || { echo "OLD and NEW are the same key." >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first." >&2; exit 1; }

start="$(git rev-parse --abbrev-ref HEAD)"
stash="$(mktemp -d "${TMPDIR:-/tmp}/rotate-plaintext.XXXXXX")"
work="$(mktemp -d "${TMPDIR:-/tmp}/rotate-check.XXXXXX")"
# Keep the plaintext folders you have now; they are put back at the end.
for d in app-src src site notes; do [ -e "$d" ] && mv "$d" "$stash/$d"; done
restore() {
  git checkout -q "$start" 2>/dev/null || true
  for d in app-src src site notes; do rm -rf "$root/$d"; [ -e "$stash/$d" ] && mv "$stash/$d" "$root/$d"; done
  rm -rf "$stash" "$work"
}
trap restore EXIT

for b in "${branches[@]}"; do
  echo "==> $b"
  git fetch -q origin "$b" 2>/dev/null || true
  git checkout -q "$b"
  git pull -q --ff-only origin "$b" 2>/dev/null || true
  grep -qx "$oldpub" keys/recipient.txt || { echo "   $b is not encrypted to the OLD key (already rotated?). Skipping."; continue; }

  rm -rf app-src src site notes "$work"/*
  [ -f encrypted/laravel.tar.gz.age ] && scripts/decrypt-app.sh "$old" app-src >/dev/null
  [ -f encrypted/site.tar.gz.age ] && scripts/decrypt.sh "$old" src >/dev/null
  [ -f encrypted/notes.tar.gz.age ] && scripts/decrypt-notes.sh "$old" notes >/dev/null

  echo "$newpub" > keys/recipient.txt
  [ -d app-src ] && FORCE=1 scripts/encrypt-app.sh >/dev/null
  [ -d src ] && scripts/encrypt.sh >/dev/null
  [ -d notes ] && FORCE=1 scripts/encrypt-notes.sh >/dev/null

  # The NEW key must give back exactly the same files; the OLD key must no longer open them.
  if [ -d app-src ]; then scripts/decrypt-app.sh "$new" "$work/app" >/dev/null && diff -rq app-src "$work/app" >/dev/null || { echo "   Check failed for laravel archive on $b." >&2; exit 1; }; fi
  if [ -d src ]; then scripts/decrypt.sh "$new" "$work/site" >/dev/null && diff -rq src "$work/site" >/dev/null || { echo "   Check failed for site archive on $b." >&2; exit 1; }; fi
  if [ -d notes ]; then scripts/decrypt-notes.sh "$new" "$work/notes" >/dev/null && diff -rq notes "$work/notes" >/dev/null || { echo "   Check failed for notes archive on $b." >&2; exit 1; }; fi
  if [ -f encrypted/laravel.tar.gz.age ] && age -d -i "$old" encrypted/laravel.tar.gz.age >/dev/null 2>&1; then echo "   The OLD key still opens the archive on $b." >&2; exit 1; fi

  git add keys/recipient.txt encrypted
  git commit -q --no-verify -m "Rotate encryption key (re-encrypted to new public key)"
  [ "$push" = 1 ] && git push -q origin "$b"
  echo "   done ($(git rev-parse --short HEAD))"
  rm -rf app-src src site notes
done

echo
echo "All branches re-encrypted to: $newpub"
echo "Next: update AGE_KEY_FILE in deploy/opalstack/opalstack.env, back up the NEW key offline, and keep the OLD key"
echo "offline only if you need to open the frozen release branches (treat it as compromised)."
