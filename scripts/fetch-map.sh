#!/usr/bin/env bash
# Download the Hong Kong map (Protomaps / OpenStreetMap vector tiles) as one .pmtiles file.
#
# Only the Hong Kong area is read from the latest Protomaps daily world build (HTTP range requests), so the
# download is tens of MB, not the whole planet. Run it wherever the file is needed:
#   - on the server (deploy):  scripts/fetch-map.sh --out "$OPAL_APP_DIR/shared/maps/hong-kong.pmtiles"
#   - on your machine (dev):   scripts/fetch-map.sh            (writes app-src/public/maps/hong-kong.pmtiles)
#
# Options
#   --out PATH         output file (default: app-src/public/maps/hong-kong.pmtiles)
#   --bbox W,S,E,N     area (default: Hong Kong 113.82,22.14,114.45,22.57)
#   --maxzoom N        most detailed zoom level to keep (default: 15; 14 is about half the size)
#   --source URL|FILE  a .pmtiles world build (default: the newest daily build found on build.protomaps.com)
#   --max-age DAYS     skip when the existing file is younger than this (default: 0 = always download)
#   --pmtiles PATH     pmtiles CLI to use (default: found on PATH, else downloaded to ~/.local/bin)
#   --dry-run          print what would happen, download nothing
#
# Writes OUT.json next to the map with the source build, bbox, zoom, size and sha256. Map data © OpenStreetMap
# contributors (ODbL): the page that shows the map must display that attribution.
set -euo pipefail
cd "$(dirname "$0")/.."

out="app-src/public/maps/hong-kong.pmtiles"
bbox="113.82,22.14,114.45,22.57"
maxzoom=15
source=""
max_age=0
pmtiles_bin=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --bbox) bbox="$2"; shift 2 ;;
    --maxzoom) maxzoom="$2"; shift 2 ;;
    --source) source="$2"; shift 2 ;;
    --max-age) max_age="$2"; shift 2 ;;
    --pmtiles) pmtiles_bin="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'fetch-map: %s\n' "$*" >&2; exit 1; }

[[ "$bbox" =~ ^-?[0-9.]+,-?[0-9.]+,-?[0-9.]+,-?[0-9.]+$ ]] || die "--bbox must be W,S,E,N in degrees"
[[ "$maxzoom" =~ ^[0-9]+$ ]] && [ "$maxzoom" -ge 8 ] && [ "$maxzoom" -le 15 ] || die "--maxzoom must be 8..15"
[[ "$max_age" =~ ^[0-9]+$ ]] || die "--max-age must be a number of days"
command -v curl >/dev/null || die "curl is required"

# Skip when the current file is recent enough.
if [ -s "$out" ] && [ "$max_age" -gt 0 ]; then
  age_days=$(( ( $(date +%s) - $(stat -c %Y "$out" 2>/dev/null || stat -f %m "$out") ) / 86400 ))
  if [ "$age_days" -lt "$max_age" ]; then
    say "Map is $age_days day(s) old (< $max_age): nothing to do. ($out)"
    exit 0
  fi
fi

# 1. pmtiles CLI (single static binary from github.com/protomaps/go-pmtiles).
find_pmtiles() {
  if [ -n "$pmtiles_bin" ]; then [ -x "$pmtiles_bin" ] || die "--pmtiles $pmtiles_bin is not executable"; return; fi
  if command -v pmtiles >/dev/null; then pmtiles_bin="$(command -v pmtiles)"; return; fi
  if [ -x "$HOME/.local/bin/pmtiles" ]; then pmtiles_bin="$HOME/.local/bin/pmtiles"; return; fi

  local os arch json url tmp
  case "$(uname -s)" in Linux) os=Linux ;; Darwin) os=Darwin ;; *) die "unsupported OS $(uname -s); install pmtiles and pass --pmtiles" ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=arm64 ;; *) die "unsupported CPU $(uname -m)" ;; esac
  say "Downloading the pmtiles tool for $os/$arch …"
  [ "$dry" = 1 ] && { pmtiles_bin="$HOME/.local/bin/pmtiles"; say "  (dry run) would install to $pmtiles_bin"; return; }
  json="$(curl -fsSL https://api.github.com/repos/protomaps/go-pmtiles/releases/latest)" || die "cannot reach api.github.com"
  url="$(printf '%s' "$json" | grep -oE "https://[^\"]+_${os}_${arch}\.(tar\.gz|zip)" | head -n 1)"
  [ -n "$url" ] || die "no go-pmtiles release asset for ${os}_${arch}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/pm.archive" "$url" || die "download failed: $url"
  case "$url" in *.zip) (cd "$tmp" && unzip -q pm.archive) ;; *) tar -xzf "$tmp/pm.archive" -C "$tmp" ;; esac
  mkdir -p "$HOME/.local/bin"
  mv "$tmp/pmtiles" "$HOME/.local/bin/pmtiles" && chmod +x "$HOME/.local/bin/pmtiles"
  rm -rf "$tmp"
  pmtiles_bin="$HOME/.local/bin/pmtiles"
}

# 2. Source: newest daily world build (files are named YYYYMMDD.pmtiles; look back up to 10 days).
find_source() {
  [ -n "$source" ] && return
  local i day
  for i in 0 1 2 3 4 5 6 7 8 9 10; do
    day="$(date -u -d "-$i day" +%Y%m%d 2>/dev/null || date -u -v-"$i"d +%Y%m%d)"
    if curl -fsI --max-time 20 "https://build.protomaps.com/$day.pmtiles" >/dev/null 2>&1; then
      source="https://build.protomaps.com/$day.pmtiles"; return
    fi
  done
  die "no daily build found on build.protomaps.com in the last 10 days (pass --source)"
}

find_pmtiles
if [ "$dry" = 1 ] && [ -z "$source" ]; then
  source="https://build.protomaps.com/<newest YYYYMMDD>.pmtiles"
else
  find_source
fi

say "Source : $source"
say "Area   : $bbox (max zoom $maxzoom)"
say "Output : $out"
if [ "$dry" = 1 ]; then
  say "(dry run) would run: $pmtiles_bin extract $source <tmp> --bbox=$bbox --maxzoom=$maxzoom"
  exit 0
fi

# 3. Extract to a temp file next to the target, check it, then swap it in (the live file is never half-written).
mkdir -p "$(dirname "$out")"
tmp_out="$out.part.$$"
trap 'rm -f "$tmp_out"' EXIT
"$pmtiles_bin" extract "$source" "$tmp_out" --bbox="$bbox" --maxzoom="$maxzoom"
"$pmtiles_bin" show "$tmp_out" >/dev/null || die "the extracted file is not a valid PMTiles archive"
[ "$(stat -c %s "$tmp_out" 2>/dev/null || stat -f %z "$tmp_out")" -gt 1000000 ] || die "the extracted file is suspiciously small"

size="$(stat -c %s "$tmp_out" 2>/dev/null || stat -f %z "$tmp_out")"
sha="$( (sha256sum "$tmp_out" 2>/dev/null || shasum -a 256 "$tmp_out") | cut -d' ' -f1)"
mv -f "$tmp_out" "$out"
trap - EXIT
chmod 644 "$out"
cat > "$out.json" <<JSON
{"source": "$source", "bbox": "$bbox", "maxzoom": $maxzoom, "bytes": $size, "sha256": "$sha", "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "attribution": "© OpenStreetMap contributors"}
JSON
say "Done: $(( size / 1024 / 1024 )) MB written to $out"
