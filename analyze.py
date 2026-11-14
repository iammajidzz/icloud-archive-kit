"""Summarize a Photos library by year: videos, RAW photos and other photos.

Run through the main script:   ./icloud-archive.sh analyze [--before 2025-11-01]
or directly:                   osxphotos run analyze.py [--before=2025-11-01]

Read-only: it only reads the Photos database.
"""

import collections
import datetime
import sys

import osxphotos


def gb(n: int) -> str:
    return f"{n / 1e9:,.1f} GB"


def kind(p) -> str:
    if p.ismovie:
        return "videos"
    if getattr(p, "israw", False) or getattr(p, "has_raw", False):
        return "raw"
    return "photos"


def main() -> None:
    before = None
    for a in sys.argv[1:]:
        if a.startswith("--before="):
            before = datetime.date.fromisoformat(a.split("=", 1)[1])

    db = osxphotos.PhotosDB()
    by_year = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))
    totals = collections.defaultdict(lambda: [0, 0])
    totals_before = collections.defaultdict(lambda: [0, 0])
    extras = collections.Counter()
    utis = collections.Counter()
    uti_bytes = collections.Counter()

    for p in db.photos():
        if getattr(p, "shared", False):  # Shared Album items don't use your storage
            extras["shared album items (ignored)"] += 1
            continue
        size = p.original_filesize or 0
        if p.hidden:
            extras["hidden (not exported)"] += 1
            extras["hidden bytes"] += size
            continue
        k = kind(p)
        y = p.date.year
        by_year[y][k][0] += 1
        by_year[y][k][1] += size
        totals[k][0] += 1
        totals[k][1] += size
        if before and p.date.date() < before:
            totals_before[k][0] += 1
            totals_before[k][1] += size
        if getattr(p, "screenshot", False):
            extras["screenshots"] += 1
        if getattr(p, "live_photo", False):
            extras["live photos"] += 1
        if getattr(p, "ismissing", False):
            extras["only in iCloud (will be downloaded)"] += 1
        utis[p.uti or "?"] += 1
        uti_bytes[p.uti or "?"] += size

    print(f"\nPhotos library: {db.library_path}\n")
    hdr = f"{'Year':<6}{'Videos':>18}{'RAW photos':>20}{'Other photos':>20}{'Year total':>14}"
    print(hdr)
    print("-" * len(hdr))
    for y in sorted(by_year):
        r = by_year[y]
        cells = [f"{r[k][0]:>6,} {gb(r[k][1]):>11}" for k in ("videos", "raw", "photos")]
        total = sum(r[k][1] for k in r)
        print(f"{y:<6}{cells[0]:>18}{cells[1]:>20}{cells[2]:>20}{gb(total):>14}")
    print("-" * len(hdr))
    cells = [f"{totals[k][0]:>6,} {gb(totals[k][1]):>11}" for k in ("videos", "raw", "photos")]
    print(f"{'All':<6}{cells[0]:>18}{cells[1]:>20}{cells[2]:>20}{gb(sum(v[1] for v in totals.values())):>14}")

    if before:
        print(f"\nCaptured before {before}:")
        for k in ("videos", "raw", "photos"):
            n, b = totals_before[k]
            print(f"  {k:<8} {n:>7,}  {gb(b)}")
        print(f"  {'total':<8} {sum(v[0] for v in totals_before.values()):>7,}  "
              f"{gb(sum(v[1] for v in totals_before.values()))}")

    print("\nOther counts:")
    for key in ("live photos", "screenshots", "only in iCloud (will be downloaded)",
                "hidden (not exported)", "shared album items (ignored)"):
        if extras[key]:
            extra = f"  ({gb(extras['hidden bytes'])})" if key.startswith("hidden") else ""
            print(f"  {key:<38} {extras[key]:>7,}{extra}")

    print("\nBiggest file types:")
    for u, b in uti_bytes.most_common(8):
        print(f"  {u:<34} {utis[u]:>7,}  {gb(b)}")
    print()


main()
