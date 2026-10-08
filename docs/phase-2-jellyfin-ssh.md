# Phase 2: SSH + Jellyfin (outline)

This becomes a full runbook once Phase 1 is done. The decisions below are already made.

## Network
- Move the server to Ethernet. Add DHCP reservations on the router for **both** the Ethernet and the Wi-Fi adapter, since the laptop sometimes moves around the house.
- Set the Windows network profile to **Private**.

## SSH (admin from the Mac)
- Use the built-in **OpenSSH Server** optional feature, with the service set to Automatic.
- **Key-only** login with an ed25519 key from the Mac; `PasswordAuthentication no`.
- Admin keys go in `C:\ProgramData\ssh\administrators_authorized_keys`, with permissions restricted to Administrators and SYSTEM. **Not** in `~/.ssh` (see [ADR 005](decisions/005-ssh-lan-only-no-rdp.md)).
- The firewall rule allows only the `LocalSubnet` on the Private profile.
- PowerShell is the default shell.
- No RDP.

## Power and updates
- No sleep or hibernate on AC. Lid close does nothing. The USB/SATA drive never powers down.
- Group Policy: install updates automatically, restart only between 04:00 and 05:00.
- After each reboot, a check confirms the Jellyfin service is running.

## Jellyfin
- Official Windows installer, installed **as a service**, running as the local user `svc-jellyfin`. That account has **read-only** access to `D:\data\media` (see [ADR 006](decisions/006-service-accounts.md)).
- Hardware transcoding: Intel **QSV**. Expect to fix GPU access under a non-SYSTEM account.
- 4K: direct play to the LG only. Transcode to 1080p for other clients if needed.
- Users: a separate admin account, plus one everyday account per person.

## Config backups
- A Windows script zips the configs (excluding cache, transcodes and trickplay). The Mac pulls the zip nightly over SSH with a `launchd` job and keeps the last 7.

## Media layout (fixed now for Phase 3)
```
D:\data\media\
├── movies\
├── tv\
└── torrents\
    ├── incomplete\
    └── completed\
```
