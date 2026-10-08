# 006: Each service runs under its own low-privilege account

**Context:**
- Jellyfin's Windows installer runs the service as **Local System** by default, which has full control of the machine. A bug in any network-facing service would then hand over the whole box.
- Another person also uses this laptop with her own account.

**Decision:**
- Each service gets its own local account with no interactive login and only the folder rights it needs:

  | Account | Access |
  |---|---|
  | `svc-jellyfin` | Read-only on `D:\data\media` |
  | `svc-qbittorrent` (Phase 3) | Write on `D:\data\media\torrents` |
  | `svc-sonarr`, `svc-radarr` (Phase 3) | Write on the library folders |

- Human accounts are separate: one local admin, and standard (non-admin) users for everyday use.

**Consequences:**
- If one service is compromised, it can only touch its own folders.
- More setup: NTFS permissions, "Log on as a service" rights, and possibly granting the GPU access Quick Sync needs outside SYSTEM.
- Group membership has to be planned so the Phase 3 apps can hardlink each other's files.
