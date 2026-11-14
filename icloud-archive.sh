#!/usr/bin/env bash
# icloud-archive.sh — copy full-quality originals out of iCloud Photos onto an
# external drive, sorted into dated folders, then verify every file.
#
# Uses osxphotos (https://github.com/RhetTbull/osxphotos). Nothing is ever
# deleted from Photos or iCloud: deleting is left to you after you've checked.
#
# Usage:
#   ./icloud-archive.sh analyze                      [--before YYYY-MM-DD]
#   ./icloud-archive.sh videos  "/Volumes/DRIVE"     [--before YYYY-MM-DD]
#   ./icloud-archive.sh raw     "/Volumes/DRIVE"     [--before YYYY-MM-DD]
#   ./icloud-archive.sh photos  "/Volumes/DRIVE"     [--before YYYY-MM-DD] [--year YYYY]
#   ./icloud-archive.sh verify  videos|raw|photos "/Volumes/DRIVE" [--before ...] [--year ...]
#
# Output on the drive:
#   iCloud Videos/2023 - 04/…      (videos: one folder per month)
#   iCloud Photos/2023/…           (RAW and other photos: one folder per year)
#   _archive-logs/                 (log + CSV report of every run)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_FOLDER_TEMPLATE='{created.year} - {created.mm}'
PHOTO_FOLDER_TEMPLATE='{created.year}'

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

command -v osxphotos >/dev/null 2>&1 || die "osxphotos is not installed. See README.md, step 1."
[[ "$(uname)" == "Darwin" ]] || die "This must run on the Mac that has the Photos library."

MODE="${1:-}"; [[ -n "$MODE" ]] || usage; shift

# ---------- analyze ----------
if [[ "$MODE" == "analyze" ]]; then
  ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --before) ARGS+=("--before=$2"); shift 2 ;;
      *) die "unknown option for analyze: $1" ;;
    esac
  done
  exec osxphotos run "$HERE/analyze.py" "${ARGS[@]+"${ARGS[@]}"}"
fi

# ---------- verify ----------
if [[ "$MODE" == "verify" ]]; then
  KIND="${1:-}"; DRIVE="${2:-}"; shift 2 || usage
  [[ "$KIND" =~ ^(videos|raw|photos)$ ]] || die "verify needs: videos, raw or photos"
  [[ -d "$DRIVE" ]] || die "drive folder not found: $DRIVE"
  ARGS=("$KIND" "$DRIVE")
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --before) ARGS+=("--before=$2"); shift 2 ;;
      --year)   ARGS+=("--year=$2");   shift 2 ;;
      *) die "unknown option for verify: $1" ;;
    esac
  done
  exec osxphotos run "$HERE/verify.py" "${ARGS[@]}"
fi

# ---------- export modes ----------
[[ "$MODE" =~ ^(videos|raw|photos)$ ]] || usage
DRIVE="${1:-}"; [[ -n "$DRIVE" ]] || usage; shift
[[ -d "$DRIVE" ]] || die "drive folder not found: $DRIVE (is the drive plugged in?)"

BEFORE=""; YEAR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) BEFORE="$2"; shift 2 ;;
    --year)   YEAR="$2";   shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -z "$BEFORE" || "$BEFORE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--before must look like 2025-11-01"
[[ -z "$YEAR"   || "$YEAR"   =~ ^[0-9]{4}$ ]]               || die "--year must look like 2023"
[[ -z "$YEAR" || "$MODE" == "photos" ]] || die "--year only applies to photos"

# Only use optional flags this osxphotos version actually has.
HELP="$(osxphotos export --help 2>/dev/null)"
has_flag() { grep -q -- "$1" <<<"$HELP"; }
for f in --download-missing --skip-edited --update --report --not-hidden --only-movies --only-photos --to-date --directory; do
  has_flag "$f" || die "your osxphotos is missing $f — run: uv tool upgrade osxphotos"
done

STAMP="$(date +%Y%m%d-%H%M%S)"
LOGDIR="$DRIVE/_archive-logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/$MODE-$STAMP.log"
REPORT="$LOGDIR/$MODE-$STAMP.csv"

COMMON=(
  --download-missing          # pull originals down from iCloud via Photos
  --skip-edited               # originals only, exactly as shot (no re-compression)
  --not-hidden                # leave the Hidden album alone
  --update                    # resumable: re-running skips what's already copied
  --report "$REPORT"
  --verbose
)
has_flag --export-aae && COMMON+=(--export-aae)        # keep your edits as .aae sidecars
has_flag --not-shared && COMMON+=(--not-shared)        # skip Shared Album items (not your storage)
has_flag --retry      && COMMON+=(--retry 3)
has_flag --touch-file && COMMON+=(--touch-file)        # file date = capture date in Finder
[[ "${USE_PHOTOKIT:-0}" == "1" ]] && has_flag --use-photokit && COMMON+=(--use-photokit)

DATE=()
if [[ -n "$YEAR" ]]; then
  DATE+=(--from-date "$YEAR-01-01" --to-date "$((YEAR + 1))-01-01")
  if [[ -n "$BEFORE" && "$BEFORE" < "$((YEAR + 1))-01-01" ]]; then DATE=(--from-date "$YEAR-01-01" --to-date "$BEFORE"); fi
elif [[ -n "$BEFORE" ]]; then
  DATE+=(--to-date "$BEFORE")
fi

ALBUM_NOTE=""
add_album() {  # tag everything archived so you can find and delete it in Photos later
  if has_flag --add-exported-to-album && has_flag --add-skipped-to-album; then
    COMMON+=(--add-exported-to-album "$1" --add-skipped-to-album "$1")
    ALBUM_NOTE="Everything copied is also added to the Photos album \"$1\"."
  fi
}

run() {
  info "osxphotos export $*"
  # caffeinate keeps the Mac awake for as long as the export runs
  caffeinate -dimsu osxphotos export "$@" 2>&1 | tee -a "$LOG"
}

case "$MODE" in
  videos)
    DEST="$DRIVE/iCloud Videos"; mkdir -p "$DEST"
    add_album "Archived to drive - Videos"
    run "$DEST" --only-movies --directory "$VIDEO_FOLDER_TEMPLATE" "${DATE[@]+"${DATE[@]}"}" "${COMMON[@]}"
    ;;
  raw)
    DEST="$DRIVE/iCloud Photos"; mkdir -p "$DEST"
    add_album "Archived to drive - RAW"
    if has_flag --query-eval; then
      # RAW-only photos (ProRAW DNG, camera RAW) and RAW+JPEG pairs
      run "$DEST" --only-photos --query-eval "photo.israw or photo.has_raw" \
          --directory "$PHOTO_FOLDER_TEMPLATE" "${DATE[@]+"${DATE[@]}"}" "${COMMON[@]}"
    else
      # Older osxphotos: one pass per common RAW file type, then RAW+JPEG pairs
      for UTI in com.adobe.raw-image com.sony.arw-raw-image com.canon.cr2-raw-image \
                 com.canon.cr3-raw-image com.nikon.raw-image com.fuji.raw-image \
                 com.panasonic.rw2-raw-image com.olympus.or-raw-image com.leica.raw-image; do
        run "$DEST" --only-photos --uti "$UTI" --directory "$PHOTO_FOLDER_TEMPLATE" \
            "${DATE[@]+"${DATE[@]}"}" "${COMMON[@]}"
      done
      run "$DEST" --only-photos --has-raw --directory "$PHOTO_FOLDER_TEMPLATE" \
          "${DATE[@]+"${DATE[@]}"}" "${COMMON[@]}"
    fi
    ;;
  photos)
    # All other photos. RAW already exported to the same folder is skipped automatically.
    DEST="$DRIVE/iCloud Photos"; mkdir -p "$DEST"
    add_album "Archived to drive - Photos"
    run "$DEST" --only-photos --directory "$PHOTO_FOLDER_TEMPLATE" "${DATE[@]+"${DATE[@]}"}" "${COMMON[@]}"
    ;;
esac

info "Export finished. Log: $LOG"
info "Report: $REPORT"
[[ -n "$ALBUM_NOTE" ]] && info "$ALBUM_NOTE"
info "Now checking every file against the library…"
VERIFY_ARGS=("$MODE" "$DRIVE")
[[ -n "$BEFORE" ]] && VERIFY_ARGS+=("--before=$BEFORE")
[[ -n "$YEAR"   ]] && VERIFY_ARGS+=("--year=$YEAR")
osxphotos run "$HERE/verify.py" "${VERIFY_ARGS[@]}" 2>&1 | tee -a "$LOG"
