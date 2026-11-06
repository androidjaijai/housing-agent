#!/usr/bin/env bash
# Deploy the encrypted Laravel app to Opalstack shared hosting FROM YOUR LOCAL MACHINE.
# The age private key stays here: we decrypt locally and rsync the plain app to the server.
#
#   opalstack-deploy.sh preflight         check local tools + server (PHP, extensions, composer, disk, shared/.env)
#   opalstack-deploy.sh first-run         create server directories; upload a .env template if none exists
#   opalstack-deploy.sh deploy [--dry-run]
#   opalstack-deploy.sh rollback          switch back to the previous release
#   opalstack-deploy.sh status            current release, release list, /health status code
#   opalstack-deploy.sh cron [--install]  print (or install, idempotently) the crontab lines
#
# Config: deploy/opalstack/opalstack.env (or OPAL_CONFIG=<path>); see opalstack.env.example.
# Env switches: SKIP_GIT_UPDATE=1, SKIP_BACKUP=1, ALLOW_NO_BACKUP=1.
# OPAL_SSH=local simulates the server on this machine (no ssh).
# Portable to macOS bash 3.2.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd -P)"
CONFIG="${OPAL_CONFIG:-$SELF_DIR/opalstack.env}"

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

WORK=""
cleanup() { if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---------------------------------------------------------------- config
[ -f "$CONFIG" ] || die "config not found: $CONFIG (copy opalstack.env.example to opalstack.env, or set OPAL_CONFIG)"
# shellcheck disable=SC1090
. "$CONFIG"
OPAL_SSH="${OPAL_SSH:-}"; OPAL_APP_DIR="${OPAL_APP_DIR:-}"; OPAL_PHP="${OPAL_PHP:-}"; OPAL_COMPOSER="${OPAL_COMPOSER:-}"
OPAL_URL="${OPAL_URL:-}"; AGE_KEY_FILE="${AGE_KEY_FILE:-}"; OPAL_SSH_OPTS="${OPAL_SSH_OPTS:-}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-claude/interactive-demo}"; KEEP_RELEASES="${KEEP_RELEASES:-5}"
export SKIP_BACKUP="${SKIP_BACKUP:-0}" ALLOW_NO_BACKUP="${ALLOW_NO_BACKUP:-0}"

is_local() { [ "$OPAL_SSH" = local ]; }

SSH_OPTS=()
if [ -n "$OPAL_SSH_OPTS" ]; then read -r -a SSH_OPTS <<< "$OPAL_SSH_OPTS"; fi
ssh_cmd() { ssh ${SSH_OPTS[@]+"${SSH_OPTS[@]}"} "$@"; }

# Run a command on the server (stdin is passed through). Arguments are shell-quoted for the remote shell.
rcmd() {
  if is_local; then "$@"; else ssh_cmd "$OPAL_SSH" "$(printf '%q ' "$@")"; fi
}
# Same, with the deploy environment exported.
rcmd_env() {
  rcmd env "OPAL_PHP=$OPAL_PHP" "OPAL_COMPOSER=$OPAL_COMPOSER" "OPAL_APP_DIR=$OPAL_APP_DIR" \
    "KEEP_RELEASES=$KEEP_RELEASES" "SKIP_BACKUP=$SKIP_BACKUP" "ALLOW_NO_BACKUP=$ALLOW_NO_BACKUP" "$@"
}

require_config() {
  local missing="" v
  for v in OPAL_SSH OPAL_APP_DIR OPAL_PHP OPAL_COMPOSER OPAL_URL AGE_KEY_FILE; do
    eval "[ -n \"\${$v}\" ]" || missing="$missing $v"
  done
  [ -z "$missing" ] || die "missing in $CONFIG:$missing"
  case "$OPAL_APP_DIR" in /*) ;; *) die "OPAL_APP_DIR must be an absolute path" ;; esac
  case "$OPAL_APP_DIR" in *[[:space:]]*) die "OPAL_APP_DIR must not contain spaces" ;; esac
}

# ---------------------------------------------------------------- portable helpers
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
abs_dir() { (cd "$1" 2>/dev/null && pwd -P); }

key_inside_repo() {
  local d; d="$(abs_dir "$(dirname "$AGE_KEY_FILE")")" || return 1
  case "$d/" in "$REPO_ROOT"/*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- preflight
PF_FAIL=0
pf() { # status name detail
  printf '  %-5s %-34s %s\n' "$1" "$2" "${3:-}"
  [ "$1" = FAIL ] && PF_FAIL=1
  return 0
}

cmd_preflight() {
  require_config
  echo "Local checks"
  local t
  for t in age rsync git curl; do
    if command -v "$t" >/dev/null 2>&1; then pf PASS "local: $t"; else pf FAIL "local: $t" "not installed"; fi
  done
  if is_local; then pf PASS "local: ssh" "not needed (OPAL_SSH=local)"
  elif command -v ssh >/dev/null 2>&1; then pf PASS "local: ssh"; else pf FAIL "local: ssh" "not installed"; fi
  if [ -f "$AGE_KEY_FILE" ]; then
    pf PASS "local: key file exists"
    if [ "$(file_mode "$AGE_KEY_FILE")" = 600 ]; then pf PASS "local: key chmod 600"
    else pf FAIL "local: key chmod 600" "run: chmod 600 <key file>"; fi
    if key_inside_repo; then pf FAIL "local: key outside repo" "move the key out of $REPO_ROOT"
    else pf PASS "local: key outside repo"; fi
  else
    pf FAIL "local: key file exists" "AGE_KEY_FILE not found"
  fi
  [ -f "$REPO_ROOT/encrypted/laravel.tar.gz.age" ] && pf PASS "local: encrypted archive" || pf FAIL "local: encrypted archive" "encrypted/laravel.tar.gz.age missing"
  [ -f "$SELF_DIR/remote-release.sh" ] && pf PASS "local: remote-release.sh" || pf FAIL "local: remote-release.sh" "missing"
  [ -f "$SELF_DIR/env.opalstack.example" ] && pf PASS "local: env.opalstack.example" || pf FAIL "local: env.opalstack.example" "missing"

  echo "Server checks ($OPAL_SSH)"
  local out rc=0
  out="$(rcmd_env bash -c "$(remote_preflight_script)" _ </dev/null 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && ! printf '%s\n' "$out" | grep -q '^\(PASS\|FAIL\)|'; then
    pf FAIL "server: connect/run" "exit $rc: $(printf '%s' "$out" | head -n 3 | tr '\n' ' ')"
  else
    local st nm dt
    while IFS='|' read -r st nm dt; do
      case "$st" in PASS|FAIL|WARN) pf "$st" "server: $nm" "$dt" ;; esac
    done <<< "$out"
  fi
  echo
  if [ "$PF_FAIL" -eq 0 ]; then echo "Preflight: ALL PASS"; else echo "Preflight: FAILED"; exit 1; fi
}

# Emits PASS|FAIL lines. .env values are never printed (only presence / emptiness).
remote_preflight_script() {
  cat <<'REMOTE'
PHP="${OPAL_PHP:?}"; APP="${OPAL_APP_DIR:?}"
case "$PHP" in /*) PATH="$(dirname "$PHP"):$PATH"; export PATH ;; esac
ok()  { printf 'PASS|%s|%s\n' "$1" "${2:-}"; }
bad() { printf 'FAIL|%s|%s\n' "$1" "${2:-}"; }
if ! command -v "$PHP" >/dev/null 2>&1 && [ ! -x "$PHP" ]; then bad "php binary" "$PHP not found"; exit 0; fi
ver="$("$PHP" -r 'echo PHP_VERSION;' 2>/dev/null || true)"
if "$PHP" -r 'exit(version_compare(PHP_VERSION,"8.3.0",">=")?0:1);' 2>/dev/null; then ok "php >= 8.3" "$ver"; else bad "php >= 8.3" "found '${ver:-unknown}'"; fi
for e in pdo_mysql intl gd zip mbstring sodium fileinfo openssl curl dom; do
  if "$PHP" -r 'exit(extension_loaded($argv[1])?0:1);' "$e" 2>/dev/null; then ok "php ext $e"; else bad "php ext $e" "not loaded in CLI php"; fi
done
# Recommended, not required by the app's production packages.
for e in bcmath; do
  if "$PHP" -r 'exit(extension_loaded($argv[1])?0:1);' "$e" 2>/dev/null; then ok "php ext $e"; else printf 'WARN|%s|%s\n' "php ext $e" "recommended; not required"; fi
done
if "$PHP" -r 'exit(function_exists("gd_info") && !empty(gd_info()["WebP Support"])?0:1);' 2>/dev/null; then ok "gd WebP support"; else bad "gd WebP support" "GD has no WebP"; fi
if "${OPAL_COMPOSER:?}" --version >/dev/null 2>&1; then ok "composer runs"; else bad "composer runs" "$OPAL_COMPOSER failed"; fi
for d in "$APP" "$APP/releases" "$APP/shared" "$APP/shared/storage"; do
  if [ -d "$d" ]; then ok "dir ${d#"$APP"}/" "exists"; else bad "dir ${d#"$APP"}/" "missing (run first-run)"; fi
done
base="$APP"; [ -d "$base" ] || base="$(dirname "$APP")"
free_mb="$(df -Pm "$base" 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "$free_mb" ] && [ "$free_mb" -ge 500 ]; then ok "free disk >= 500MB" "${free_mb}MB"; else bad "free disk >= 500MB" "${free_mb:-unknown}MB"; fi
env="$APP/shared/.env"
if [ -f "$env" ]; then
  ok "shared/.env exists"
  m="$(stat -c %a "$env" 2>/dev/null || true)"
  if [ "$m" = 600 ]; then ok "shared/.env chmod 600"; else bad "shared/.env chmod 600" "mode ${m:-?}"; fi
  if grep -Eq '^APP_KEY=.+' "$env"; then ok "APP_KEY set"; else bad "APP_KEY set" "empty"; fi
  if grep -Eq '^MAIL_ADMIN_ADDRESS=[^[:space:]]+@[^[:space:]]+' "$env"; then ok "MAIL_ADMIN_ADDRESS set"; else bad "MAIL_ADMIN_ADDRESS set" "empty/invalid: composer's package:discover fails (backup config)"; fi
  if grep -Eiq '^APP_DEBUG=(false|0)[[:space:]]*$' "$env"; then ok "APP_DEBUG=false"; else bad "APP_DEBUG=false" "must be false"; fi
else
  bad "shared/.env exists" "missing (run first-run, then edit it)"
fi
REMOTE
}

# ---------------------------------------------------------------- first-run
cmd_first_run() {
  require_config
  local tpl="$SELF_DIR/env.opalstack.example"
  [ -f "$tpl" ] || die "missing $tpl"
  log "Creating directories under $OPAL_APP_DIR"
  rcmd bash -c '
    set -e
    a=$1
    mkdir -p "$a/releases" "$a/shared/storage/app/public" "$a/shared/storage/app/private" \
      "$a/shared/storage/framework/cache/data" "$a/shared/storage/framework/sessions" \
      "$a/shared/storage/framework/views" "$a/shared/storage/logs"
    chmod 700 "$a/shared"' _ "$OPAL_APP_DIR" </dev/null
  if rcmd test -f "$OPAL_APP_DIR/shared/.env" </dev/null; then
    log "shared/.env already exists; left untouched"
  else
    log "Uploading .env template to shared/.env (chmod 600)"
    rcmd bash -c 'umask 077; cat > "$1/shared/.env.new" && chmod 600 "$1/shared/.env.new" && mv -n "$1/shared/.env.new" "$1/shared/.env"; rm -f "$1/shared/.env.new"' _ "$OPAL_APP_DIR" < "$tpl"
  fi
  cat <<EOF

Next steps
  1. Opalstack dashboard: create the MariaDB database + user, a "Symlink" app whose target is
       $OPAL_APP_DIR/current/public
     and a site (HTTPS) that uses that app.
  2. Generate an APP_KEY locally (cd to a decrypted copy, or any Laravel 13 checkout):
       php artisan key:generate --show
  3. Edit the server file and fill in APP_KEY, APP_URL, DB_*, MAIL_*, ANTHROPIC_API_KEY, ...:
       ${OPAL_SSH}:$OPAL_APP_DIR/shared/.env
     (e.g. ssh ${OPAL_SSH} then nano $OPAL_APP_DIR/shared/.env)
  4. $0 preflight
  5. $0 deploy --dry-run   then   $0 deploy
  6. $0 cron --install
EOF
}

# ---------------------------------------------------------------- deploy
decrypt_to() { # dest dir (empty)
  local enc="$REPO_ROOT/encrypted/laravel.tar.gz.age" shaf="$REPO_ROOT/encrypted/laravel.tar.gz.age.sha256" want got arc
  [ -f "$enc" ] || die "$enc not found"
  command -v age >/dev/null 2>&1 || die "age is not installed"
  if [ -f "$shaf" ]; then
    want="$(awk '{print $1; exit}' "$shaf")"; got="$(sha256_of "$enc")"
    [ "$want" = "$got" ] || die "checksum mismatch: encrypted/laravel.tar.gz.age was changed or corrupted"
  fi
  arc="$WORK/laravel.tar.gz"
  age -d -i "$AGE_KEY_FILE" "$enc" > "$arc" || die "age decryption failed (wrong key?)"
  if [ ! -s "$arc" ] || ! gzip -t "$arc" 2>/dev/null; then die "decryption produced no valid archive"; fi
  tar -xzf "$arc" -C "$1"
  rm -f "$arc"
}

git_update() {
  if [ "${SKIP_GIT_UPDATE:-0}" = 1 ]; then log "Skipping git update (SKIP_GIT_UPDATE=1)"; return; fi
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    die "working tree has uncommitted changes; commit/stash them (or SKIP_GIT_UPDATE=1)"
  fi
  log "Updating repository ($DEPLOY_BRANCH)"
  git -C "$REPO_ROOT" fetch --prune origin
  git -C "$REPO_ROOT" checkout "$DEPLOY_BRANCH"
  git -C "$REPO_ROOT" pull --ff-only origin "$DEPLOY_BRANCH"
}

cmd_deploy() {
  local dry=0
  case "${1:-}" in "") ;; --dry-run) dry=1 ;; *) die "unknown option: $1" ;; esac
  require_config
  command -v rsync >/dev/null 2>&1 || die "rsync is not installed"
  [ -f "$AGE_KEY_FILE" ] || die "AGE_KEY_FILE not found: $AGE_KEY_FILE"
  if key_inside_repo; then die "AGE_KEY_FILE must not be inside the repository"; fi
  git_update

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/opalstack-deploy.XXXXXX")"
  chmod 700 "$WORK"
  local ts stage dest
  ts="$(date +%Y%m%d%H%M%S)"
  stage="$WORK/app"; mkdir -p "$stage"
  log "Decrypting locally (release $ts)"
  decrypt_to "$stage"
  cp "$SELF_DIR/remote-release.sh" "$stage/remote-release.sh"

  if is_local; then dest="$OPAL_APP_DIR/releases/$ts/"; else dest="$OPAL_SSH:$OPAL_APP_DIR/releases/$ts/"; fi
  local rs=(-rlptz --delete --exclude=/vendor --exclude=/node_modules --exclude=/.env --exclude=/storage
            --exclude=/tests '--exclude=*.sqlite' '--exclude=.phpunit*')
  if ! is_local; then rs+=(-e "ssh $OPAL_SSH_OPTS"); fi

  if [ "$dry" = 1 ]; then
    log "rsync --dry-run to $dest"
    rsync "${rs[@]}" --dry-run --stats "$stage/" "$dest" | tail -n 20
    log "Dry run complete: nothing activated."
    return
  fi

  rcmd test -d "$OPAL_APP_DIR/releases" </dev/null || die "$OPAL_APP_DIR/releases missing; run first-run"
  log "Uploading to $dest"
  rsync "${rs[@]}" "$stage/" "$dest"
  cleanup; WORK=""   # the decrypted copy is no longer needed

  log "Activating on server"
  rcmd_env bash "$OPAL_APP_DIR/releases/$ts/remote-release.sh" activate "$ts" </dev/null
  log "Done. Check: $0 status"
}

# ---------------------------------------------------------------- rollback / status / cron
push_helper() { # copies remote-release.sh to the server; prints its path
  local p="$OPAL_APP_DIR/.remote-release.sh"
  rcmd bash -c 'cat > "$1"' _ "$p" < "$SELF_DIR/remote-release.sh"
  printf '%s' "$p"
}

cmd_rollback() {
  require_config
  local h; h="$(push_helper)"
  rcmd_env bash "$h" rollback </dev/null
}

cmd_status() {
  require_config
  local h code; h="$(push_helper)"
  rcmd_env bash "$h" status </dev/null
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${OPAL_URL%/}/health" 2>/dev/null || true)"
  echo "health  : ${OPAL_URL%/}/health -> HTTP ${code:-000}"
}

cron_lines() {
  awk -v php="$OPAL_PHP" -v app="$OPAL_APP_DIR" '
    function rep(s, k, v,   o, i) { o = ""; while ((i = index(s, k)) > 0) { o = o substr(s, 1, i - 1) v; s = substr(s, i + length(k)) } return o s }
    { $0 = rep($0, "OPAL_APP_DIR", app); $0 = rep($0, "OPAL_PHP", php); print }
  ' "$SELF_DIR/crontab.opalstack.txt"
}

CRON_BEGIN="# BEGIN housing-agent (managed by opalstack-deploy.sh)"
CRON_END="# END housing-agent"

cmd_cron() {
  require_config
  case "${1:-}" in
    "") cron_lines ;;
    --install)
      if is_local; then warn "OPAL_SSH=local: not touching your real crontab. Lines would be:"; cron_lines; return; fi
      local existing merged
      WORK="$(mktemp -d "${TMPDIR:-/tmp}/opalstack-cron.XXXXXX")"
      existing="$WORK/existing"; merged="$WORK/merged"
      rcmd crontab -l > "$existing" 2>/dev/null </dev/null || : > "$existing"
      awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b {skip=1; next} $0 == e {skip=0; next} !skip' "$existing" > "$merged"
      { cat "$merged"; echo "$CRON_BEGIN"; cron_lines; echo "$CRON_END"; } > "$WORK/new"
      rcmd crontab - < "$WORK/new"
      log "Crontab installed (managed block replaced; other entries kept)"
      rcmd crontab -l </dev/null | awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b {p=1} p {print} $0 == e {p=0}'
      ;;
    *) die "usage: cron [--install]" ;;
  esac
}

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  preflight) cmd_preflight ;;
  first-run) cmd_first_run ;;
  deploy)    shift; cmd_deploy "$@" ;;
  rollback)  cmd_rollback ;;
  status)    cmd_status ;;
  cron)      shift; cmd_cron "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
