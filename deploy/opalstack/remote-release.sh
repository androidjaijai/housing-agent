#!/usr/bin/env bash
# Runs ON THE SERVER (Opalstack shared hosting; Linux/GNU userland assumed). Called by opalstack-deploy.sh.
#
#   remote-release.sh activate <timestamp>   build + migrate + atomically switch to releases/<timestamp>
#   remote-release.sh rollback               switch back to the previous release
#   remote-release.sh status                 show current release and the release list
#
# Environment (passed by the local script):
#   OPAL_APP_DIR (required)  OPAL_PHP (default php)  OPAL_COMPOSER (default composer)  KEEP_RELEASES (default 5)
#   SKIP_BACKUP=1 skip the pre-migration DB backup   ALLOW_NO_BACKUP=1 continue if that backup fails
#
# Layout: $OPAL_APP_DIR/{releases/<ts>, shared/.env, shared/storage, current -> releases/<ts>}
set -Eeuo pipefail

APP="${OPAL_APP_DIR:?OPAL_APP_DIR is not set}"
PHP="${OPAL_PHP:-php}"
COMPOSER="${OPAL_COMPOSER:-composer}"
KEEP="${KEEP_RELEASES:-5}"
REL="$APP/releases"
SHARED="$APP/shared"
CUR="$APP/current"

# Make "#!/usr/bin/env php" (composer, artisan child processes) resolve to the configured PHP.
case "$PHP" in /*) PATH="$(dirname "$PHP"):$PATH"; export PATH ;; esac

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

case "$KEEP" in ''|*[!0-9]*) die "KEEP_RELEASES must be a number" ;; esac
[ "$KEEP" -ge 2 ] || KEEP=2

current_name() { local t; t="$(readlink "$CUR" 2>/dev/null || true)"; [ -n "$t" ] && basename "$t" || true; }
release_names() { [ -d "$REL" ] && ls -1 "$REL" | grep -E '^[0-9]{14}$' | sort -r || true; }

switch_to() { # <release name>
  ln -sfn "releases/$1" "$APP/current.tmp"
  mv -T "$APP/current.tmp" "$CUR"
}

artisan_has() { "$PHP" artisan list --raw 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

prune() {
  local cur prev keep_n=0 name
  cur="$(current_name)"
  prev="$(release_names | awk -v c="$cur" '$0 != c {print; exit}')"
  # prev: newest release other than current (approximation of "previous"); callers pass the real one via PREV_RELEASE.
  prev="${PREV_RELEASE:-$prev}"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    keep_n=$((keep_n + 1))
    if [ "$keep_n" -le "$KEEP" ] || [ "$name" = "$cur" ] || [ "$name" = "$prev" ]; then continue; fi
    log "Pruning $name"
    rm -rf "${REL:?}/$name"
  done < <(release_names)
}

cmd_activate() {
  local ts="${1:-}" rel previous switched=0
  [[ "$ts" =~ ^[0-9]{14}$ ]] || die "usage: remote-release.sh activate <YYYYmmddHHMMSS>"
  rel="$REL/$ts"
  [ -d "$rel" ] || die "release directory $rel does not exist"
  [ -f "$SHARED/.env" ] || die "$SHARED/.env is missing (run: opalstack-deploy.sh first-run)"
  previous="$(current_name)"

  # Any failure before the switch removes the half-built release; the live site is never touched.
  trap 'rc=$?; if [ "$rc" -ne 0 ] && [ "$switched" -eq 0 ]; then echo "Deploy failed (exit $rc): removing incomplete release $ts. The live site was not touched." >&2; cd "$APP"; rm -rf "$rel"; fi' EXIT

  log "Linking shared .env and storage"
  mkdir -p "$SHARED/storage/app/public" "$SHARED/storage/app/private" "$SHARED/storage/framework/cache/data" \
           "$SHARED/storage/framework/sessions" "$SHARED/storage/framework/views" "$SHARED/storage/logs"
  rm -rf "$rel/storage"
  ln -s "$SHARED/storage" "$rel/storage"
  ln -sfn "$SHARED/.env" "$rel/.env"
  mkdir -p "$rel/bootstrap/cache"
  cd "$rel"

  log "composer install --no-dev"
  COMPOSER_MEMORY_LIMIT=-1 "$COMPOSER" install --no-dev --no-interaction --prefer-dist --optimize-autoloader

  log "storage:link"
  "$PHP" artisan storage:link --relative --force

  if [ "${SKIP_BACKUP:-0}" = 1 ]; then
    log "Pre-migration backup skipped (SKIP_BACKUP=1)"
  elif [ -z "$previous" ]; then
    log "Pre-migration backup skipped (first deploy, nothing to protect yet)"
  elif ! artisan_has backup:run; then
    log "Pre-migration backup skipped (backup:run not available in this release)"
  else
    log "Database backup before migrating"
    if ! "$PHP" artisan backup:run --only-db --disable-notifications; then
      if [ "${ALLOW_NO_BACKUP:-0}" = 1 ]; then warn "pre-migration backup failed; continuing (ALLOW_NO_BACKUP=1)"
      else die "pre-migration backup failed. Fix it, or re-run with ALLOW_NO_BACKUP=1 / SKIP_BACKUP=1"; fi
    fi
  fi

  log "migrate --force"
  "$PHP" artisan migrate --force

  log "optimize"
  "$PHP" artisan optimize
  if artisan_has filament:optimize; then "$PHP" artisan filament:optimize || warn "filament:optimize failed (ignored)"; fi

  log "Smoke test: artisan about"
  "$PHP" artisan about >/dev/null

  log "Switching current -> releases/$ts"
  switch_to "$ts"
  switched=1
  trap - EXIT

  log "Restarting queue workers"
  (cd "$CUR" && "$PHP" artisan queue:restart) || warn "queue:restart failed (workers pick up new code on their next start anyway)"

  PREV_RELEASE="$previous" prune
  log "Deployed $ts (previous: ${previous:-none})"
  echo "Note: PHP-FPM opcache may serve the old code for a short while (realpath cache); it refreshes by itself within ~2 minutes."
}

cmd_rollback() {
  local cur prev
  cur="$(current_name)"
  [ -n "$cur" ] || die "no current release"
  prev="$(release_names | awk -v c="$cur" '$0 < c {print; exit}')"
  [ -n "$prev" ] || die "no older release to roll back to"
  log "Rolling back $cur -> $prev"
  switch_to "$prev"
  cd "$CUR"
  "$PHP" artisan optimize || warn "optimize failed"
  "$PHP" artisan queue:restart || warn "queue:restart failed"
  log "Now on $prev"
  echo "Note: database migrations are NOT reverted. If $cur added migrations, restore from a backup if the old code cannot cope."
}

cmd_status() {
  local cur
  cur="$(current_name)"
  echo "app dir : $APP"
  echo "current : ${cur:-none}"
  echo "releases:"
  release_names | while IFS= read -r n; do
    if [ "$n" = "$cur" ]; then echo "  * $n (current)"; else echo "    $n"; fi
  done
  [ -f "$SHARED/.env" ] && echo "shared/.env: present" || echo "shared/.env: MISSING"
}

case "${1:-}" in
  activate) shift; cmd_activate "$@" ;;
  rollback) cmd_rollback ;;
  status)   cmd_status ;;
  *) echo "usage: $0 activate <timestamp> | rollback | status" >&2; exit 2 ;;
esac
