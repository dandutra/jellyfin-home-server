# 006: Each service runs under its own low-privilege account

**Context:**
- Jellyfin's Windows installer offers two accounts for its service: **Local System**, which has full control of the machine, and **Network Service**, its default. A bug in a network-facing service running as Local System would hand over the whole box.
- Network Service is shared by many built-in Windows services. Any folder access granted to it is granted to all of them.
- Every Jellyfin upgrade runs the old uninstaller, which deletes the `JellyfinServer` service, and then creates it again on the installer's account (see `nsis/jellyfin.nsi` in [jellyfin-server-windows](https://github.com/jellyfin/jellyfin-server-windows)). Any other account we set is lost on upgrade.
- Another person also uses this laptop with her own account.

**Decision:**
- Each service runs as its own **virtual account**, `NT SERVICE\<service name>`. Windows creates this account for one service only. It has no password and can't sign in interactively.

  | Account | Access |
  |---|---|
  | `NT SERVICE\JellyfinServer` | Read-only on `D:\data\media`; modify on `C:\ProgramData\Jellyfin\Server` |
  | `NT SERVICE\qBittorrent` | Modify on `D:\data\media` and `C:\ProgramData\qBittorrent` |
  | `NT SERVICE\Sonarr`, `NT SERVICE\Radarr` | Modify on `D:\data\media` and their own `C:\ProgramData\<App>` |
  | `NT SERVICE\Prowlarr` | Modify on `C:\ProgramData\Prowlarr` only; nothing on `D:` |
  | `NT SERVICE\<Bazarr service>` | Modify on `D:\data\media` (it saves subtitles next to the videos) and `C:\ProgramData\Bazarr` |

- [`setup-jellyfin-service.ps1`](../../scripts/windows/setup-jellyfin-service.ps1) sets Jellyfin's account and permissions, and gets re-run after every Jellyfin upgrade. [`setup-arr-services.ps1`](../../scripts/windows/setup-arr-services.ps1) does the same for the Phase 3 apps, and gets re-run after any of their installers runs again.
- Human accounts are separate: one local admin, and standard (non-admin) users for everyday use.

**Consequences:**
- If one service is compromised, it can only touch its own folders.
- No service passwords to store or rotate.
- The account's identity comes from the service name, so folder permissions survive an upgrade. Only the service's account setting has to be put back.
- Forgetting to re-run the script after an upgrade leaves Jellyfin on Network Service. It still works, just with the shared account.
- Quick Sync under a non-SYSTEM account may need extra GPU access. Step 10 of the Phase 2 runbook tests it.
- An NTFS file has one set of permissions shared by all its hardlinks. A file qBittorrent downloads keeps the permissions it got in `torrents`, even after Sonarr or Radarr links it into `tv` or `movies`.

**Changed 2026-10-19 (Phase 3):** the four download apps and Bazarr get virtual accounts too. Each one gets Modify on the whole `D:\data\media` tree instead of only the folders it uses. With hardlinks sharing one set of permissions, the narrower version saved little and added room for mistakes. Prowlarr only talks to the other apps and gets nothing on `D:`. The Sonarr, Radarr, Prowlarr and Bazarr installers create their services on LocalService or Local System and do so again on every reinstall. Their built-in updaters keep the account we set.

**Changed 2026-10-19:** the first version used a local user `svc-jellyfin` with a password. Virtual accounts do the same isolation without a password, and keep working across upgrades with no password prompt.
