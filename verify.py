"""Check that every photo/video that should have been archived is on the drive,
with exactly the original file size Photos has for it.

Run through the main script:  ./icloud-archive.sh verify videos "/Volumes/DRIVE" [--before 2025-11-01]
or directly:                  osxphotos run verify.py videos "/Volumes/DRIVE" [--before=2025-11-01] [--year=2023]

Read-only on both sides. Writes a missing-<kind>.csv to _archive-logs if anything is missing.
"""

import collections
import csv
import datetime
import os
import re
import sys

import osxphotos

SKIP_EXT = {".aae", ".db", ".csv", ".log", ".json", ".xmp"}


def strip_dup(name: str) -> str:
    """'IMG_0175 (1).DNG' -> 'img_0175.dng' (exporters add ' (n)' on name clashes)."""
    stem, ext = os.path.splitext(name)
    return (re.sub(r" \(\d+\)$", "", stem) + ext).lower()


def wanted(p, kind: str, before, year) -> bool:
    if getattr(p, "shared", False) or p.hidden:
        return False
    if before and p.date.date() >= before:
        return False
    if year and p.date.year != year:
        return False
    is_raw = getattr(p, "israw", False) or getattr(p, "has_raw", False)
    if kind == "videos":
        return p.ismovie
    if kind == "raw":
        return (not p.ismovie) and is_raw
    return not p.ismovie  # photos: every still image (RAW included)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: verify.py videos|raw|photos DRIVE [--before=YYYY-MM-DD] [--year=YYYY]")
    kind, drive = sys.argv[1], sys.argv[2]
    before = year = None
    for a in sys.argv[3:]:
        if a.startswith("--before="):
            before = datetime.date.fromisoformat(a.split("=", 1)[1])
        elif a.startswith("--year="):
            year = int(a.split("=", 1)[1])

    root = os.path.join(drive, "iCloud Videos" if kind == "videos" else "iCloud Photos")
    if not os.path.isdir(root):
        sys.exit(f"Not found: {root}")

    on_drive = collections.defaultdict(set)  # name -> sizes
    n_files = total_bytes = 0
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.startswith(".") or os.path.splitext(f)[1].lower() in SKIP_EXT:
                continue
            try:
                s = os.path.getsize(os.path.join(dirpath, f))
            except OSError:
                continue
            on_drive[strip_dup(f)].add(s)
            n_files += 1
            total_bytes += s

    db = osxphotos.PhotosDB()
    expected = [p for p in db.photos() if wanted(p, kind, before, year)]
    ok, missing = 0, []
    exp_bytes = 0
    for p in expected:
        name = (p.original_filename or p.filename or "").lower()
        size = p.original_filesize
        exp_bytes += size or 0
        sizes = on_drive.get(strip_dup(name), set())
        if sizes and (size is None or size in sizes):
            ok += 1
        else:
            missing.append(p)

    print(f"\nVerify {kind}: {root}")
    if before:
        print(f"  captured before {before}")
    if year:
        print(f"  year {year}")
    print(f"  expected from Photos : {len(expected):,} items, {exp_bytes / 1e9:,.2f} GB")
    print(f"  on the drive         : {n_files:,} files, {total_bytes / 1e9:,.2f} GB "
          "(includes Live Photo clips and RAW+JPEG partners)")
    print(f"  matched exactly      : {ok:,}")
    print(f"  MISSING              : {len(missing):,}")

    if missing:
        logdir = os.path.join(drive, "_archive-logs")
        os.makedirs(logdir, exist_ok=True)
        out = os.path.join(logdir, f"missing-{kind}.csv")
        with open(out, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["filename", "date", "size_bytes", "uuid"])
            for p in missing:
                w.writerow([p.original_filename, p.date.isoformat(), p.original_filesize, p.uuid])
        for p in missing[:20]:
            print(f"    {p.original_filename}  {p.date:%Y-%m-%d}  {(p.original_filesize or 0) / 1e6:,.0f} MB")
        if len(missing) > 20:
            print(f"    … and {len(missing) - 20} more")
        print(f"\n  Full list: {out}")
        print("  Fix: run the same export command again — it only fetches what's missing.")
        sys.exit(1)
    print("\n  All good: every item is on the drive at its original size.")
    print("  It is now safe to delete these from Photos if you want the iCloud space back.\n")


main()
