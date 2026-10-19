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

## 2026-10-16: Clean install

- **F2 didn't open the BIOS**, not even with Fn. Windows Fast Startup makes the boot too quick to catch. I opened it from Windows instead: Settings → Recovery → Advanced startup → UEFI Firmware Settings.
- The BIOS has Dell's newer setup screen, not the classic menu tree the runbook assumed. Its search box found every setting: AHCI, USB boot, Secure Boot, Primarily AC Use, Wake on AC, and the USB stick first in the boot order (after the AHCI switch, the old Windows can't start, so the Windows route works only once).
- Setup asked for neither a product key nor an edition. It read the Pro key from the firmware.
- **Setup listed the new SSD as Disk 0 and the old NVMe as Disk 1**, the opposite of the runbook. I went by size: deleted the four partitions on the 238 GB disk and left the 477 GB SSD and the USB stick alone.
- **Local account:** on build 26300 the network screen has no "continue without internet" option. `Shift + F10` → `start ms-cxh:localonly` worked straight from that screen and opened the local-account dialog. No `autounattend.xml` needed.
- Activation failed offline ("can't connect"), as expected. On Wi-Fi it activated within minutes: **Windows 11 Pro, Active**.

## 2026-10-17: The install that only booted with the stick in

- Windows Update stayed on "Checking for updates" for a long time. I closed the lid overnight, and the next sign-in hung. I forced a power-off.
- After that, the laptop didn't find Windows. Dell SupportAssist ran its hardware scan (passed), wanted Ethernet to download its recovery environment, and looped. The BIOS boot list had only the network entries.
- **Cause:** Windows Setup had put the boot files on the USB stick's EFI partition, which macOS creates when it formats a stick as GPT. It booted fine only while the stick was in. See [roadblock 003](docs/roadblocks/003-boot-files-on-the-usb-stick.md).
  - Fixed from the running Windows: shrank C: by 300 MB, created an EFI partition on the NVMe and ran `bcdboot`. The laptop now boots with no stick.
  - `build-usb.sh` now formats the stick as MBR, so there is no EFI partition for Setup to reuse.
- Windows turned on BitLocker device encryption by itself: C: is encrypted, but protection is off and there's no recovery key yet. I first picked TPM-only protection, then changed my mind once I understood it only guards against someone taking the laptop or the drive. The server stays in the apartment, so I'm decrypting C: instead. See [ADR 009](docs/decisions/009-no-bitlocker.md).
- The SSD reports as 512 GB (T-FORCE), not 500.
- **Antivirus:** Defender only on the server, no Kaspersky. See [ADR 008](docs/decisions/008-defender-only.md).

## 2026-10-17: Post-install, Phase 1 done

- Windows Update, then Dell Command | Update. Renamed the laptop to `homeserver`.
- Turned off device encryption and decrypted C: (ADR 009). It finished at *FullyDecrypted*, 0%.
- Formatted the SSD as GPT + NTFS, `D:` `Media`, quick format, no compression.
- **Restore:** I used Cut instead of Copy on the share for one account's files, which removed them from the Mac before I had checked them on the laptop. Nothing was lost, but the runbook now says to copy. We went through the backup together and kept only what we needed. Most of it was old downloads.
- `pre-wipe-checks.ps1` after the install: Windows 11 Pro, Licensed (firmware OEM key), AHCI controller, both drives visible. Before the install, the controller was in RAID mode (Intel RST).
- There's an empty profile named `WsiAccount` that I didn't create. To look at in Phase 2.

## 2026-10-19: Phase 2 starts

- Deleted the backup on the Mac. Dell Command | Update says the drivers are up to date, so the Intel graphics driver for Quick Sync is in place.
- Turned the Phase 2 outline into a runbook, with scripts for SSH, power and updates, the Jellyfin service and the nightly config backup.
- **Jellyfin's account changed.** Reading the installer source showed two things: its default is Network Service, not Local System, and every upgrade deletes and re-creates the service on that account. A local user `svc-jellyfin` would need its password typed after every upgrade. A virtual account (`NT SERVICE\JellyfinServer`) has no password, and its permissions survive the re-create. [ADR 006](docs/decisions/006-service-accounts.md) is updated.

## 2026-10-19: BIOS, network, SSH

- BIOS: SupportAssist OS Recovery and its threshold off, Windows Boot Manager first, the old USB entry gone.
- Ethernet plugged in, DHCP reservations for both adapters on the router, both networks set to Private. Setting a network to Private doesn't change internet access. It only tells the firewall to trust other devices at home.
- **SSH works from the Mac with the key**, and a password login is refused without a prompt. A failed login still listed `keyboard-interactive` as a method. I tested it with a wrong password ready, and Windows never asked for one, but `setup-ssh.ps1` now turns it off too. Now a failed login lists only `publickey`.
- **`WsiAccount`** is a disabled account that Windows manages itself, for "Web Sign-in scenarios" (its own description). It was created on 2026-10-17. Its profile is a default one, about 600 small files. Left as it is.

## 2026-10-19: Power, updates, test files

- The first SSH attempt timed out: the laptop had gone to sleep, because step 5 is the one that stops it sleeping. I woke it at the keyboard.
- `set-power-and-updates.ps1` worked first time: no sleep on AC, screen off after 5 minutes, hibernation off, updates at 04:00, active hours 05:00–23:00. The lid line in its output was blank. "Lid close action" is a hidden setting, so `powercfg /query` skips it. `powercfg /qh` shows it as *Do nothing* on AC. The script now uses `/qh`.
- The laptop only has Modern Standby (S0). S3 sleep doesn't exist on it.
- Test files are on D:: *Big Buck Bunny* 1080p H.264 (Blender only serves it as a zip now) and Jellyfin's `Test Jellyfin 4K HEVC 10bit 40M.mp4`. My hash check said `False` on the HEVC clip, but the file was fine: PowerShell 5.1 returned the `.sha256sum` file as bytes, so I was comparing against garbage. The hash and the size both match the published values. The runbook now decodes the bytes first.

## 2026-10-19: Jellyfin installed, own account

- Installed Jellyfin 12.2 at the laptop: Advanced, as a service, Network Service. The installer said the service couldn't start, but it was running. Its log ended in `Startup complete 0:01:15`, the health page said `Healthy`, and Windows had no service errors. The first start sets up the database and probes ffmpeg, and the installer most likely stopped waiting before that. Later starts take 7 seconds.
- ffmpeg 8.1.3 ships with the `*_qsv` decoders and encoders, so Quick Sync should be available.
- `setup-jellyfin-service.ps1` failed at icacls with exit code 1332, because over SSH `USERDOMAIN` is `WORKGROUP`. The script now uses the admin account's SID. See [roadblock 004](docs/roadblocks/004-icacls-workgroup-over-ssh.md). The three untested parts all worked: `sc config ... obj= "NT SERVICE\JellyfinServer"` with no password, icacls resolving the `NT SERVICE\` name, and `sc failureflag`.
- Jellyfin now runs as `NT SERVICE\JellyfinServer`. It has read-only access to `D:\data` and modify rights on its data folder. Ports 8096 and 7359 are open to the home network only, and the Mac gets `Healthy` from it.

## 2026-10-19: First-run setup and Quick Sync

- First-run wizard done in the Mac's browser: Jellyfin admin account, Movies and Shows libraries, remote connections on, automatic port mapping off. Both test files showed up. The server log warns that the `tv` library is empty, which it is.
- I first opened the user menu's *Settings → Playback* by mistake. That page holds per-user preferences. The server's Quick Sync settings are under the admin *Dashboard → Playback → Transcoding*.
- Before the dashboard test, I ran Jellyfin's ffmpeg over SSH: 4K HEVC 10-bit to 720p H.264 on Quick Sync, at 119 fps (2× real-time).
- **The dashboard test worked under `NT SERVICE\JellyfinServer`:** D3D11VA decode, `vpp_qsv` scaling and `h264_qsv` encode, 150 fps (2.4× real-time), `FFmpeg exited with code 0`. The virtual account needed no extra rights for the GPU, which had been the expected trouble spot.
- The CPU check from the runbook didn't work: the clip was fully converted in 12 seconds, before I looked. The ffmpeg log's `fps` and `speed` are the measure now.

## 2026-10-19: TVs, and a Fire TV that wouldn't start one file

- LG (Jellyfin for webOS 1.2.2): both test files played. There was no transcode log for the 4K clip, so it played directly, as [ADR 004](docs/decisions/004-4k-direct-play-only.md) plans.
- Fire TV (Jellyfin Android TV 0.19.10): the 4K clip was converted to 1080p with Quick Sync. *Big Buck Bunny* never started. The app retried direct play about three times a second for over ten minutes and never asked the server for a transcode.
- I narrowed it down with 2-minute ffmpeg copies, changing one thing per copy. Every rewritten copy played: MP4 with 5.1, MP4 with stereo, and MOV without the timecode track. After the MOV copy, I blamed the timecode track. Then the full-length MP4 kept that track and still played, so that conclusion was wrong. The cause is something in the original 2008 file's packaging. I had already deleted the original, so I can't say what exactly. See [roadblock 005](docs/roadblocks/005-fire-tv-retry-loop-on-old-mov.md).
- Fix: repackaged Big Buck Bunny as `Big Buck Bunny (2008).mp4` with `-c copy`, so nothing was re-encoded. Step 6 now does this straight after the download.

## 2026-10-19: Nightly config backup

- `backup-jellyfin-config.ps1 -Register` worked first time. The task runs as SYSTEM, so the problem from roadblock 004 (the script naming the current user) doesn't apply here.
- A test run with `Start-ScheduledTask` took about 12 seconds, including the Jellyfin stop and start. The zip is 3.9 MB and holds `config`, `data`, `metadata`, `plugins` and `root`, with no cache or logs. Only SYSTEM and Administrators can read the backup folder.
- My first check showed no zip, but the zip was there. PowerShell's formatter had dropped part of the output because one command returned objects of several types. Running the checks one at a time showed it.
- The Mac pulled the zip by hand, then again from launchd with `launchctl kickstart`. macOS 15 didn't block the background job from reaching the home network. The 03:30 and 03:50 runs haven't happened yet, so the log is worth a look tomorrow.
- Each run logged "Pseudo-terminal will not be allocated". It came from `ssh -G`, which only prints the config, when stdin isn't a terminal. The script now passes `-T` there.

## 2026-10-19: Reboot test, Phase 2 done

- `Restart-Computer -Force` over SSH. Windows was up 43 seconds later, SSH answered after about 66 seconds and Jellyfin's health page said `Healthy` after about 71.
- Nobody signed in at the laptop: no `explorer.exe` was running. `sshd` and `JellyfinServer` were both Running, and Jellyfin still ran as `NT SERVICE\JellyfinServer`.
- Big Buck Bunny played on the Fire TV two minutes after the restart. The log shows one start and no retry loop.
- Phase 2 is done. Two Phase 2 jobs haven't run on schedule yet, the 03:30 backup and the 03:50 pull. Phase 3 (qBittorrent, Sonarr, Radarr, Prowlarr) gets its own planning session first.

## 2026-10-19: Phase 3 planned

- The first scheduled backup runs tonight (03:30 on the server, 03:50 on the Mac). The log had only the manual test this afternoon.
- Planned Phase 3 in a question-and-answer session. The app list grew by Bazarr, for English and Brazilian Portuguese subtitles from a free OpenSubtitles.com account.
- qBittorrent goes through NordVPN, which I already pay for. I asked about Gluetun, the container most guides use as a VPN kill switch. It needs Docker, which [ADR 002](docs/decisions/002-native-windows-no-docker.md) rules out, and Docker Desktop only starts after someone signs in. The native version is a WireGuard tunnel service plus two layers that each stop leaks on their own: qBittorrent bound to the tunnel's adapter, and a firewall rule blocking it on Ethernet and Wi-Fi ([ADR 010](docs/decisions/010-vpn-kill-switch-native.md)).
- Nord only offers incoming ports with a paid add-on, so there's no port forward. Downloads come only from peers that accept connections.
- qBittorrent has no Windows service mode, so it runs under NSSM, from its own copy, not Jellyfin's ([ADR 011](docs/decisions/011-qbittorrent-under-nssm.md)).
- Every app gets its own virtual account. I went for Modify on all of `D:\data\media` for the apps that write there instead of per-folder rights: hardlinked files share one set of permissions anyway. Prowlarr gets nothing on `D:` ([ADR 006](docs/decisions/006-service-accounts.md), updated).
- Found while checking the server: the NordVPN Windows app was installed today, with three services using about 650 MB of RAM. The server had 2 GB free of 8 with Jellyfin idle. The runbook removes the app first.
- Written: [Phase 3 runbook](docs/phase-3-arr-stack.md), `setup-vpn-tunnel.ps1`, `setup-arr-services.ps1`, `backup-arr-config.ps1`, and the Mac pull script now also pulls the Phase 3 zip and logs the VPN status. Nothing installed yet.

## 2026-10-19: Phase 3 step 1, NordVPN app removed

- Uninstalled NordVPN and NordUpdater at the laptop and restarted. No Nord services, adapters, drivers, uninstall entries or program folders are left.
- A minute after the restart, with nobody signed in, the server had 4.2 GB of RAM free. Before, it had 2.0 GB, but someone was signed in then too, so the two numbers don't compare exactly.

## 2026-10-19: Phase 3 step 2, WireGuard tunnel

- WireGuard for Windows 1.1.1 installed at the laptop. Nord's manual-setup page gave a WireGuard config for a Toronto server: one peer, `AllowedIPs = 0.0.0.0/0`, plus DNS and keepalive lines.
- `setup-vpn-tunnel.ps1` worked first time: `WireGuardTunnel$nord-wg` is running and set to Auto, the handshake came after 1 second, and Nord's IP check says `protected: True`.
- The routing table now has `0.0.0.0/1` and `128.0.0.0/1` on `nord-wg` (metric 5). The default route stays on Ethernet (metric 25) but loses to the two more specific routes. SSH and Jellyfin's health check still answer from the Mac.
- Only SYSTEM and Administrators can read `C:\ProgramData\homeserver\vpn`. I deleted the downloaded copy of the config.
- Not tested yet: the tunnel connecting at boot with nobody signed in. Step 11 covers it.

## 2026-10-19: Phase 3 step 3, qBittorrent

- qBittorrent installed at the laptop without the installer's firewall rule or file associations, then run once with `--profile=C:\ProgramData\qBittorrent` to set the options. Its settings live in `C:\ProgramData\qBittorrent\qBittorrent\config\qBittorrent.ini`.
- qBittorrent 5 writes the bound adapter's name to `Session\InterfaceName`. `Session\Interface` holds an ID (`iftype53_32768`). The script's bind check read the wrong key, so I fixed it before the first run.
- First run of `setup-arr-services.ps1` stopped at once: it granted rights to `NT SERVICE\qBittorrent` before creating the service, and Windows can't resolve a virtual account until its service exists. I moved the grant below the install, and the second run went through.
- Result: `qBittorrent: Running, runs as NT SERVICE\qBittorrent`, `bound to nord-wg`. It runs in session 0 and uses about 53 MB of RAM. The web page answers from the Mac on port 8080.
- qBittorrent listens only on `nord-wg` addresses, and the external IP it detected isn't the home one. The kill-switch block rule covers `Wi-Fi` and `Ethernet`. The script also turned off the two inbound rules Windows made when I clicked Cancel on the firewall prompt.
- The kill switch itself gets tested in step 4.
