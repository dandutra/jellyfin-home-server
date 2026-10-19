# 010: qBittorrent goes through NordVPN, with a native kill switch

**Context:**
- Every peer in a torrent swarm sees the downloader's public IP, and so does the internet provider. The content is legal ([README](../../README.md#content)), so this is about privacy. I already pay for NordVPN.
- The server runs with nobody signed in. NordVPN's docs only describe its Windows app connecting after a sign-in ("Launch at Windows startup" plus "Auto-connect"). If it doesn't connect, qBittorrent would sit on the bare connection after every reboot.
- Gluetun is the usual answer on Linux: qBittorrent runs in a container whose only network is the VPN container. On Windows that needs Docker Desktop on WSL2, which [ADR 002](002-native-windows-no-docker.md) rules out. Docker Desktop also starts only after a sign-in, and a Linux VM writing to `D:` through WSL's file sharing makes hardlinks between it and Sonarr/Radarr hard to trust.
- Nord's account page offers WireGuard (NordLynx) config files for manual setup ("Set up NordVPN manually"). The official WireGuard for Windows client runs a config as a Windows service that connects at boot.
- WireGuard for Windows turns on its own kill switch when a config routes `0.0.0.0/0`. That kill switch also blocks the LAN, which would cut off SSH, Jellyfin and the web pages.
- NordVPN only offers port forwarding with its Dedicated Server add-on ([Nord support](https://support.nordvpn.com/hc/en-us/articles/46022896056593)).

**Decision:**
- WireGuard for Windows runs Nord's config as the tunnel service `WireGuardTunnel$nord-wg`. The NordVPN app is not installed on the server.
- The config routes `0.0.0.0/1` and `128.0.0.0/1` instead of `0.0.0.0/0`. That sends all internet traffic through the tunnel, keeps the LAN direct, and leaves WireGuard's own kill switch off. This is the workaround WireGuard documents.
- The kill switch has two layers, and each one stops a leak by itself:
  1. qBittorrent is bound to the `nord-wg` adapter (Advanced → Network interface). With the tunnel down, the adapter is gone and qBittorrent has nothing to send on.
  2. A Windows Firewall rule blocks `qbittorrent.exe` outbound on the physical adapters (Ethernet, Wi-Fi). Replies to the web page still work, because the firewall checks outbound rules when a connection starts, not on replies to an accepted inbound one.
- No incoming port: no router forward, UPnP/NAT-PMP off in qBittorrent.
- The config file holds the tunnel's private key. It lives in `C:\ProgramData\homeserver\vpn` (Administrators and SYSTEM only), never in this repo and never in the nightly backup. A new one can be downloaded from Nord at any time.
- The nightly backup task writes `VPN: up` or `VPN: DOWN` to the status file the Mac logs.

**Consequences:**
- The tunnel is tied to the one Nord server picked when downloading the config. If Nord retires it, the tunnel stops, qBittorrent stops, and the nightly status says `VPN: DOWN`. The fix is a new config file and one script run.
- Windows can't route a single app through a VPN, so all of the server's internet traffic goes through Nord: Windows Update, Jellyfin's metadata lookups, Sonarr and Radarr searches. The LAN, SSH and the TVs don't.
- DNS lookups made by Windows for qBittorrent (tracker names) may still go to the router's DNS, because the tunnel doesn't own the default route. They show which tracker hosts are contacted, not the downloader's IP to peers. Accepted.
- Without an incoming port, downloads come only from peers that accept connections. Slower, but nothing on the server is reachable from the internet.
- The kill switch is proven by a test (runbook step 4), not assumed: stop the tunnel during a download and watch the traffic.
- Phase 3 runbook: [phase-3-arr-stack.md](../phase-3-arr-stack.md).
