# 005: SSH is key-only and LAN-only; no RDP

**Context:**
- The server is managed from a Mac.
- Jellyfin, and the Phase 3 apps, all have web UIs, so day-to-day admin never needs the Windows desktop.
- Nobody watches from outside the house.

**Decision:**
- **SSH server:** the built-in Windows OpenSSH Server.
- **Login:** ed25519 keys only; password authentication is off.
- **Firewall:** only allows the local subnet, on the Private profile.
- **No RDP**, and no ports forwarded on the router.

**Consequences:**
- From outside the home network, nothing reaches the server.
- Admin keys must go in `C:\ProgramData\ssh\administrators_authorized_keys`, not `~\.ssh\authorized_keys`. Windows OpenSSH ignores the per-user file for members of Administrators, a common trap. The file also needs strict permissions (Administrators and SYSTEM only), or sshd silently ignores it.
- Any task that needs the GUI means walking over to the laptop. That's rare and acceptable.
