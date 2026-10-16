# Journal

A dated log of the build. Short entries; anything that took real effort to solve gets its own write-up in [`docs/roadblocks/`](docs/roadblocks/). No IPs, service tags, usernames or file names in here.

## 2026-10-06: Planning

- Starting point: Dell Latitude 3410 (i5-10210U, 8 GB, 256 GB NVMe), Windows 11 Pro, years of use and likely malware. The plan: wipe it and turn it into a Jellyfin server.
- Chose a **clean install from USB** over "Reset this PC", because the reset runs from the install I don't trust. See [ADR 001](docs/decisions/001-clean-install-over-reset.md).
- The i5-10210U is a laptop chip, so the server is a laptop. That brings laptop problems: battery wear, lid behaviour, sleep, Wi-Fi.
- My wife still uses the laptop now and then. So: separate standard (non-admin) accounts, and Jellyfin runs as a Windows service that doesn't depend on who's logged in.
- **Budget:** ~$100 CAD.

## 2026-10-08: Planning, continued

- **Battery report:** design capacity 40.0 Wh, full charge capacity 6.5 Wh (**16% health**), no swelling. It stays in, with Dell's *Primarily AC Use* charge mode, and gets replaced later outside the budget.
- **Storage plan changed with prices:** the cheapest 1 TB SSD was $179 CAD and a 1 TB 2.5" HDD wasn't cheaper, so I bought a **500 GB SATA SSD**. That's enough because media gets deleted after watching and downloads will be hardlinked, not copied. See [ADR 003](docs/decisions/003-separate-media-drive.md).
- **Install USB has to be built on a Mac** (no other Windows PC). The expected problem is FAT32's 4 GiB file limit vs. the >4 GiB `install.wim`. The plan is to split it with wimlib (`scripts/mac/build-usb.sh`).
- **Licensing:** Windows reports a digital license linked to a Microsoft account, but **there's no product key stored in firmware**. Setup will therefore ask for the edition, and I must pick Pro by hand.
- **4K:** only the LG TV can play 4K. The Fire TV Stick is 1080p. 4K is direct play only; the UHD 620 can't realistically convert 4K HDR to SDR on the fly. See [ADR 004](docs/decisions/004-4k-direct-play-only.md).
- **Scope:** decided to add a Phase 3 (qBittorrent + Sonarr/Radarr/Prowlarr). Its folder layout is fixed now so hardlinks will work later. See [ADR 007](docs/decisions/007-config-and-media-layout.md).
- **Backup drive:** the only external drive is also the photo backup drive, and it has already been connected to this laptop. It gets a full ClamAV scan from the Mac along with the backup.

## 2026-10-16: Phase 1 begins

- Confirmed the laptop is listed under the Microsoft account that holds the digital license. That's the fallback if reactivation fails.
- Opened the case (out of runbook order, since the tools arrived first) and cleaned the fan and heatsink.
- **The 2.5" bay already has the SATA cable and bracket**, so no AliExpress order and no 10–12 day wait. The SSD goes in while the case is open.
- SSD installed. The old Windows lists it as "Not Initialized" in Disk Management. Left it alone; it gets formatted after the clean install.
- Ran `pre-wipe-checks.ps1`:
  - **Correction to 2026-10-08:** the firmware *does* hold a key, `Professional OEM:DM`. The earlier manual check came back empty, but the script run as Administrator found it. Setup should pick Pro on its own.
  - Both disks show bus type `RAID` under "Intel RST Premium", which confirms the BIOS is in RAID On mode. Switching to AHCI before the install is required, not optional.
  - The backup is small, ~15 GB in total. The biggest folder is a Downloads folder, mostly installers, which the backup script skips.
  - **Script bug:** listing `C:\Users` by folder name picked up localized junctions and template profiles ("All Users" and "Default User" show up under their Portuguese names). Fixed by enumerating real profiles via `Win32_UserProfile` (`Special = False`).
- BIOS 1.39.0 is already Dell's latest for the 3410, so the BIOS flash step is skipped.
- **Changed the backup target:** at ~15 GB the backup fits on the Mac, so it now goes over SMB (macOS File Sharing) and the photo drive never touches this laptop. The backup script takes `-Destination` (a drive root or a `\\host\share` path) instead of a drive letter.
  - Expected trap: drives mapped in a normal window are invisible in an elevated one (UAC split token), and the script needs Administrator to read both profiles. The runbook uses `net use \\host\share` plus the UNC path in the elevated window instead.
- The laptop runs Kaspersky, which puts Defender in passive mode. The pre-backup scan is a Kaspersky full scan, not Defender Offline. Two real-time scanners on one machine conflict.

## 2026-10-16: Scans, backup and install USB

- **Kaspersky full scan** of the laptop: 0 threats. The report had about 5,500 other entries: files inside archives it could not unpack, a few password-protected PDFs and locked browser-cache files. None were detections.
- **Photo drive scan:** the first ClamAV run took 6 seconds and scanned 0 files, but still reported "clean". `clamscan --recursive` finds nothing on the read-only NTFS mount that macOS uses. Fixed by passing an explicit file list, and the script now fails if it scans 0 files. See [roadblock 001](docs/roadblocks/001-clamscan-scanned-nothing.md).
  - Full scan: 212,747 files, 265.77 GiB, 0 infected, 4 hours.
  - `Autorun.inf` and an `.exe` at the drive root looked like USB-worm traces. They are the drive maker's factory files from 2018, and the autorun only sets the drive icon.
- **Backup to the Mac** worked on the third run: 3,161 files, 12 GB, 0 failures. Run 1 failed with robocopy error 2 on nested folders. Run 2 failed because robocopy copied the Read-only attribute of the shell folders, and macOS SMB turned it into a lock. See [roadblock 002](docs/roadblocks/002-robocopy-to-macos-smb.md).
  - ClamAV scan of the backup: 3,176 files (with the robocopy logs), 4.42 GiB scanned, 0 infected.
  - An iPhone backup on the laptop is outside the script's folders. It was left out on purpose, because the photo drive already has a copy.
- **Install USB:** the Windows 11 ISO is build 26300. The wimlib split made 3 parts from a 7.7 GB `install.wim`. The image lists Windows 11 Pro. I bought a 32 GB stick because no store had 16 GB ones.
  - The last step, `diskutil eject`, failed because Spotlight had started to index the new volume. The script now puts a `.metadata_never_index` file on the stick and forces the unmount after `sync`.
