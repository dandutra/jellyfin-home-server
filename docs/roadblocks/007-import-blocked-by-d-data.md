# 007: Radarr couldn't import because it couldn't list `D:\data`

**Phase:** 3 · **Date:** 2026-10-21 · **Time lost:** ~20 min

## Problem
The end-to-end test download finished in qBittorrent, but Radarr's queue stayed on **Import blocked** with "Failed to import movie" and "Movie has already been imported". It had created the film's folder under `movies\`, but left it empty. Nothing was linked or copied.

## What I tried
1. Took the queue message at face value. "Already imported" was misleading: the history had only the `grabbed` event and the film had no file. The download held a 4K `.mkv` plus a smaller `.mp4`. The `.mkv` import threw an error, and the `.mp4` was then rejected as a second copy of the same film.
2. Checked ACLs on the source file, `movies\` and the new folder. `NT SERVICE\Radarr` had inherited Modify on all three, and D: is NTFS with hardlink support.
3. Found the real error in Radarr's log: `System.UnauthorizedAccessException: Access to the path 'D:\data' is denied`, thrown from `PathExtensions.GetActualCasing` inside `DiskTransferService.TransferFile`.

## Root cause
Before hardlinking, Radarr resolves the exact casing of the target path. It does that by listing each parent folder for the next name down, all the way to the drive root. Phase 2 cut inheritance on `D:\data` so that only Jellyfin (read) and administrators could open it. The app accounts got Modify one level lower, on `D:\data\media`, so listing `D:\data` failed. Sonarr shares that code, and Bazarr writes next to the media, so both were exposed too.

## Fix
`setup-arr-services.ps1` now grants qBittorrent, Sonarr, Radarr and Bazarr `RX` on `D:\data` itself, with no inheritance. They can see the folder names in `D:\data`, but nothing below it except `media`. I applied the four grants by hand, with no service restarts, then ran **Refresh Monitored Downloads** in Radarr. It imported within a minute, and `fsutil hardlink list` showed two names for the file.

## What I learned
Least privilege on a folder tree has to account for how the app walks the path, not only where it writes. A grant that starts partway down the tree can break code that looks upward. When an app's error message doesn't add up, the stack trace in its log usually does.
