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
