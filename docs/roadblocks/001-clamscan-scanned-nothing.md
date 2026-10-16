# 001: ClamAV reported "clean" after scanning 0 files

**Phase:** 1 · **Date:** 2026-10-16 · **Time lost:** ~30 min

## Problem
I scanned the external photo drive from the Mac with `scripts/mac/scan-backup.sh`, which runs `clamscan --recursive` on the volume. A drive with hundreds of GB finished in 6 seconds. The summary said:

```
Scanned directories: 1
Scanned files: 0
Infected files: 0
```

`clamscan` exited 0, and the script printed "Clean: no infected files found."

## What I tried
1. Checked that macOS let Terminal read the drive. `ls` listed every folder, so permissions were not the problem.
2. Scanned one file by path. `clamscan` read it and reported `OK`, so the engine and the signatures worked.
3. Ran `clamscan -r` on a small subfolder that holds a file. It still scanned 0 files. Recursion was the broken part.
4. Built a file list with `find -type f` and passed it with `--file-list`. It scanned 4,362 files (15.7 GiB) on the same drive.

## Root cause
macOS mounts NTFS drives read-only through its own driver. On that mount, `clamscan --recursive` walks into no folder and finds no files, yet it treats an empty scan as success and exits 0.

## Fix
`scan-backup.sh` now lists the files with `find` and passes the list to `clamscan --file-list`. If `clamscan` scans 0 files, the script exits with code 2 and does not print "Clean" ([15cb6ff](https://github.com/dandutra/jellyfin-home-server/commit/15cb6ff)). The full drive scan then took 4 hours: 212,747 files, 265.77 GiB, 0 infected.

## What I learned
A security check that passes when it checked nothing is worse than no check. Exit code 0 only says the tool did not crash. Before I trust a "clean" result, I compare the files scanned with the files I expected.
