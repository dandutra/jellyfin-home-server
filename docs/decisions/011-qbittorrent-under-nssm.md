# 011: qBittorrent runs as a service through NSSM

**Context:**
- qBittorrent has no Windows service mode. There is no official Windows build of `qbittorrent-nox`, and the feature request ([qBittorrent#2070](https://github.com/qbittorrent/qBittorrent/issues/2070)) was closed as a duplicate.
- Without a service, qBittorrent only runs while someone is signed in, and it can't run as a virtual account ([ADR 006](006-service-accounts.md)).
- Two wrappers turn any program into a service: NSSM, last released in 2017 and the one Jellyfin's installer ships, and WinSW, maintained but with its 3.x line still in alpha. A scheduled task at boot is simpler but doesn't restart a crashed program.
- Jellyfin's uninstaller removes `C:\Program Files\Jellyfin\Server`, including its `nssm.exe`, on every upgrade.

**Decision:**
- qBittorrent runs as the service `qBittorrent`, created with NSSM and running as `NT SERVICE\qBittorrent`.
- NSSM is a separate copy in `C:\ProgramData\homeserver\bin\nssm.exe` (Administrators and SYSTEM only), so a Jellyfin upgrade can't pull it out from under qBittorrent.
- qBittorrent starts with `--profile=C:\ProgramData\qBittorrent`, so its settings live next to the other apps' configs ([ADR 007](007-config-and-media-layout.md)) instead of in the virtual account's profile.
- The settings are made once in qBittorrent's own window, at the laptop, with the same `--profile`. After that the service runs it with no window and it's managed from the web page.
- [`setup-arr-services.ps1`](../../scripts/windows/setup-arr-services.ps1) creates the service and is safe to run again.

**Consequences:**
- NSSM restarts qBittorrent after a crash, and it starts at boot with nobody signed in.
- The GUI build runs without a desktop. A dialog qBittorrent opens there can't be answered, so first-run prompts (legal notice, WebUI) have to be dealt with in the one GUI run.
- Upgrading qBittorrent (`winget upgrade qBittorrent.qBittorrent`) replaces the program files only. The service, its account and the profile stay.
- NSSM is unmaintained. It is a small program that has worked unchanged for years; if it ever breaks, WinSW is the replacement.
