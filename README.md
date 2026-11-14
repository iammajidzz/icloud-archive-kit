# iCloud Photos → external drive archive kit

Copies **full-quality originals** out of iCloud Photos onto an external drive,
sorted into dated folders, then checks every file against the library.
It never deletes anything from Photos or iCloud. You do that yourself once
the check passes.

It's the same job we ran by hand on the first Mac, automated with
[osxphotos](https://github.com/RhetTbull/osxphotos):

| Command | What it copies | Folders on the drive |
|---|---|---|
| `videos` | Every video, original as shot | `iCloud Videos/2023 - 04/` |
| `raw` | ProRAW / camera RAW photos (and RAW+JPEG pairs) | `iCloud Photos/2023/` |
| `photos` | All other photos (Live Photo clips included) | `iCloud Photos/2023/` |

Any edits you made in Photos are kept as small `.aae` files next to the originals.

---

## 1. One-time setup on the other Mac

1. Sign in to the **other iCloud account** in System Settings and turn on
   **iCloud Photos**. Let Photos finish syncing. "Optimize Mac Storage" is fine:
   the script downloads originals as it goes.
2. Open **Terminal** and install osxphotos:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   # close and reopen Terminal, then:
   uv tool install --python 3.13 osxphotos
   osxphotos --version
   ```
   (On macOS 12, use `--python 3.11` instead.)
3. Give Terminal access: **System Settings → Privacy & Security**
   - **Full Disk Access** → turn on **Terminal**
   - **Photos** → turn on **Terminal** if it's listed
   - The first run will also ask to let Terminal control **Photos**. Click **Allow**.
4. Copy this folder anywhere (e.g. `~/icloud-archive-kit`), then:
   ```bash
   cd ~/icloud-archive-kit
   chmod +x icloud-archive.sh
   ```
5. Plug in the external drive and find its name: `ls /Volumes`

## 2. Look before you copy (read-only)

```bash
./icloud-archive.sh analyze --before 2025-11-01
```
This shows counts and sizes per year for videos, RAW and other photos, plus
what falls before your cutoff. Check the total fits on the drive:
`df -h "/Volumes/My Passport"`.

## 3. Run the exports

Swap in your drive name and cutoff date (`--before` means *captured before*;
leave it off to take everything):

```bash
./icloud-archive.sh videos "/Volumes/My Passport" --before 2025-11-01
./icloud-archive.sh raw    "/Volumes/My Passport"
./icloud-archive.sh photos "/Volumes/My Passport" --before 2025-11-01
# or one year at a time:
./icloud-archive.sh photos "/Volumes/My Passport" --year 2023
```

- **Keep Photos open and the drive plugged in.** The script keeps the Mac awake by itself.
- Big libraries take hours (we saw about 20 GB/hour).
- **Interrupted? Just run the same command again.** It skips everything
  already copied and only fetches what's left.
- Each run ends with an automatic verification (step 4).
- Logs and a CSV of every file go to `_archive-logs/` on the drive.

## 4. Verify (runs automatically, or by hand)

```bash
./icloud-archive.sh verify videos "/Volumes/My Passport" --before 2025-11-01
./icloud-archive.sh verify raw    "/Volumes/My Passport"
./icloud-archive.sh verify photos "/Volumes/My Passport" --before 2025-11-01
```
Use the same `--before` / `--year` you exported with. It checks that every
expected item is on the drive at **exactly** its original byte size. If
anything is missing, it lists the files and saves `_archive-logs/missing-*.csv`.
Re-run the export to fetch them.

## 5. Free the iCloud space (manual, only after verify says "All good")

Everything copied is added to a Photos album: **Archived to drive - Videos**,
**- RAW** or **- Photos**.

1. Spot-check a few files on the drive. Open some videos and RAWs.
2. In Photos, open the album, press ⌘A, then Delete.
3. Open **Recently Deleted** → **Delete All** to get the space back now.
   Otherwise iCloud keeps them for 30 days.

Deleting in Photos removes them from **every device** on that iCloud account.

## Options

| Setting | How |
|---|---|
| Folder names | Edit `VIDEO_FOLDER_TEMPLATE` / `PHOTO_FOLDER_TEMPLATE` at the top of the script (e.g. `{created.year}/{created.mm}`). Change it before the first run. |
| Faster iCloud downloads | `USE_PHOTOKIT=1 ./icloud-archive.sh …` (experimental in osxphotos; doesn't work in iTerm2) |
| Hidden album | Skipped on purpose. Unhide items first if you want them copied. |
| Shared Albums | Skipped. They don't count against your storage. |

## Troubleshooting

- **"osxphotos is not installed"**: redo step 1.2, then open a new Terminal window.
- **Permission / "not authorized" errors**: recheck step 1.3, then quit and reopen Terminal.
- **A few files keep failing to download**: open Photos, find them (names are in
  `missing-*.csv`), let them load, then re-run the export.
- **Drive filling up**: run `photos` one `--year` at a time and check `df -h` between runs.
