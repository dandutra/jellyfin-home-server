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
  | Phase 3 services | Write on `D:\data\media\torrents` or the library folders, as each needs |

- [`setup-jellyfin-service.ps1`](../../scripts/windows/setup-jellyfin-service.ps1) sets the account and permissions, and gets re-run after every Jellyfin upgrade.
- Human accounts are separate: one local admin, and standard (non-admin) users for everyday use.

**Consequences:**
- If one service is compromised, it can only touch its own folders.
- No service passwords to store or rotate.
- The account's identity comes from the service name, so folder permissions survive an upgrade. Only the service's account setting has to be put back.
- Forgetting to re-run the script after an upgrade leaves Jellyfin on Network Service. It still works, just with the shared account.
- Quick Sync under a non-SYSTEM account may need extra GPU access. Step 10 of the Phase 2 runbook tests it.
- Group membership has to be planned so the Phase 3 apps can hardlink each other's files.

**Changed 2026-10-19:** the first version used a local user `svc-jellyfin` with a password. Virtual accounts do the same isolation without a password, and keep working across upgrades with no password prompt.
