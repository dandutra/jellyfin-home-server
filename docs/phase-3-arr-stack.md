# Phase 3: Downloads and automation

Goal: the server finds, downloads, renames and files legal content by itself, fetches subtitles for it, and Jellyfin plays it. qBittorrent only ever talks to the internet through NordVPN.

**Starts from:** Phase 2 done. Jellyfin runs as `NT SERVICE\JellyfinServer`, `D:\data\media` exists, SSH works from the Mac, and the nightly backup runs.
**Done when:** qBittorrent, Prowlarr, Radarr, Sonarr and Bazarr run as services under their own accounts, the kill switch passed its test, one Internet Archive item went from search to TV with a hardlink and subtitles, the Mac's nightly log shows `VPN: up`, and everything comes back after a reboot with nobody signed in.

> Same rules as before: anything surprising goes in [`JOURNAL.md`](../JOURNAL.md), anything that took a while goes in [`docs/roadblocks/`](roadblocks/), and output with IPs, MAC addresses or usernames goes in `local/`.

**What runs where:**

| App | Job | Web page (LAN only) | Account |
|---|---|---|---|
| WireGuard | Tunnel to NordVPN, connects at boot | none | SYSTEM |
| qBittorrent | Downloads torrents, only through the tunnel | `:8080` | `NT SERVICE\qBittorrent` |
| Prowlarr | Keeps the list of search sources (Internet Archive) and hands it to Radarr and Sonarr | `:9696` | `NT SERVICE\Prowlarr` |
| Radarr | Movies: searches, sends to qBittorrent, renames, hardlinks into `movies\` | `:7878` | `NT SERVICE\Radarr` |
| Sonarr | TV: the same, into `tv\` | `:8989` | `NT SERVICE\Sonarr` |
| Bazarr | Subtitles in English and Brazilian Portuguese, saved next to the videos | `:6767` | `NT SERVICE\Bazarr` |

Why it's built this way: [ADR 006](decisions/006-service-accounts.md) (accounts), [007](decisions/007-config-and-media-layout.md) (folders and hardlinks), [010](decisions/010-vpn-kill-switch-native.md) (VPN and kill switch), [011](decisions/011-qbittorrent-under-nssm.md) (qBittorrent as a service).

**Sources are legal only.** Prowlarr gets one source, Internet Archive. This repo never names other sources or titles, and screenshots of the web pages either show public-domain titles only or crop the titles out.

**Logins.** Every web page needs a login, including from the LAN. Each app gets its own strong password, saved in the password manager. Don't use the "disable for local addresses" option in Sonarr, Radarr or Prowlarr: it let callers skip the login by faking a header (CVE-2026-30975).

The installers are graphical, so they happen at the laptop. Everything after each install runs over SSH from the Mac. The scripts go to `$HOME\homeserver-scripts` on the server with `scp`, as in Phase 2.

---

## 1. Remove the NordVPN app (at the laptop)

The NordVPN Windows app is installed on the server. It runs three services (VPN, Threat Protection, updater) that use about 650 MB of the 8 GB of RAM, and its docs only describe connecting after someone signs in. The server connects with WireGuard instead ([ADR 010](decisions/010-vpn-kill-switch-native.md)). Threat Protection is also a second security product next to Defender, which [ADR 008](decisions/008-defender-only.md) rules out.

1. **Settings → Apps → Installed apps**: uninstall **NordVPN**, then **NordUpdater** if it's still listed.
2. Restart.
3. Check over SSH that nothing is left: `Get-Service *nord*` prints nothing. Its adapters (`NordLynx`, `OpenVPN Data Channel Offload for NordVPN`) should be gone from `Get-NetAdapter`.

The NordVPN app on your other devices isn't affected. The subscription stays the same.

## 2. WireGuard tunnel to NordVPN

**At the laptop:**

1. Install **WireGuard for Windows** from <https://www.wireguard.com/install/>.
2. Download a WireGuard config from your Nord account: **Nord Account → NordVPN → Advanced settings → Set up NordVPN manually**. Nord sends a code to your email. Then **Server recommendation**, pick a server in your country, **Get setup configuration → WireGuard → Download config**. Save it to `Downloads`.

   This file holds the private key for the tunnel. Anyone with the file can use your VPN, so don't email it or put it on the USB stick.

**Over SSH:**

3. ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-vpn-tunnel.ps1 -ConfigPath $HOME\Downloads\<file>.conf
   ```
   [`setup-vpn-tunnel.ps1`](../scripts/windows/setup-vpn-tunnel.ps1):
   - changes the config's routes from `0.0.0.0/0` to `0.0.0.0/1, 128.0.0.0/1`. All internet traffic still goes through Nord, but WireGuard's own kill switch stays off, so the LAN keeps working
   - saves it as `C:\ProgramData\homeserver\vpn\nord-wg.conf`, readable only by Administrators and SYSTEM
   - installs the service `WireGuardTunnel$nord-wg`, which starts at boot
4. The output should say `Running`, a handshake a few seconds ago, and `Nord says protected: True`.
5. Delete the downloaded file: `Remove-Item $HOME\Downloads\<file>.conf`.
6. From the Mac, check the LAN still works: `ssh homeserver hostname` answers, and `curl http://<server-ip>:8096/health` says `Healthy`.

If Nord ever retires that server, the tunnel stops and the Mac's nightly log says `VPN: DOWN`. Download a new config and run the script again.

## 3. qBittorrent

qBittorrent has no service mode, so NSSM runs it as one ([ADR 011](decisions/011-qbittorrent-under-nssm.md)). Its settings are made once in its own window, because as a service it has no window to show a dialog in.

**At the laptop:**

1. Install qBittorrent (64-bit) from <https://www.qbittorrent.org/download>. Installer options:
   - **Add Windows Firewall rule**: off. It would let the internet connect in. The setup script makes the rules.
   - **Disable Windows path length limit**: on. Some torrents have very long file names.
   - **Associate .torrent files** and **magnet links**: off. A double-click on the desktop would start a second copy with the default profile.
   - **Run qBittorrent** on the last page: off. It has to start with the profile below.
2. Start it once with the server's profile folder. Press **Win+R** and run:
   ```
   "C:\Program Files\qBittorrent\qbittorrent.exe" --profile=C:\ProgramData\qBittorrent
   ```
3. Accept the legal notice. If Windows Firewall asks whether to allow qBittorrent, click **Cancel**. The setup script opens only what's needed. Cancel can leave inbound block rules for `qbittorrent.exe`, which would also block the web page; the script turns them off.
4. **Tools → Options**:

   | Page | Setting | Value | Why |
   |---|---|---|---|
   | Behaviour | Show qBittorrent in notification area | **Off** | As a service, closing the window must quit it, not hide it |
   | Behaviour | Confirm on exit when torrents are active | **Off** | Nobody can answer that dialog when the service stops |
   | Downloads | Default Save Path | `D:\data\media\torrents\completed` | [ADR 007](decisions/007-config-and-media-layout.md) |
   | Downloads | Keep incomplete torrents in | **On**, `D:\data\media\torrents\incomplete` | |
   | Connection | Use UPnP / NAT-PMP port forwarding from my router | **Off** | Nothing opens ports on the router |
   | BitTorrent | When ratio reaches | **On**, `2` | Seed a while, then stop |
   | BitTorrent | When total seeding time reaches | **On**, `20160` min (14 days) | |
   | BitTorrent | then | **Stop torrent** | Radarr and Sonarr refuse a qBittorrent that removes torrents itself. Their **Remove Completed** deletes the stopped torrent and its download copy after import. The library copy is a hardlink and stays |
   | BitTorrent | Enable Local Peer Discovery to find more peers | **Off** | It announces on the home network, outside the tunnel |
   | Advanced | Network interface | **nord-wg** | Kill switch, layer 1: no tunnel, no traffic |
   | Advanced | Optional IP address to bind to | **All IPv4 addresses** | The tunnel is IPv4 only |
   | Web UI | Web User Interface (Remote control) | **On**, port `8080` | |
   | Web UI | Use UPnP / NAT-PMP to forward the port from my router | **Off** | |
   | Web UI | Authentication | your own username (not `admin`) and a strong password from the password manager | |
   | Web UI | Bypass authentication for clients on localhost | **Off** | Every app logs in |

5. **OK**, then **File → Exit**. Don't leave it running.

**Over SSH:**

6. ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-arr-services.ps1
   ```
   [`setup-arr-services.ps1`](../scripts/windows/setup-arr-services.ps1) does what it can for the apps installed so far and skips the rest. This time it:
   - copies NSSM from Jellyfin's folder to `C:\ProgramData\homeserver\bin` and creates the `qBittorrent` service, started with `--profile=C:\ProgramData\qBittorrent`
   - switches it to `NT SERVICE\qBittorrent` with restart after a crash
   - gives it Modify on its profile folder and on `D:\data\media`
   - opens port 8080 to the LAN only
   - adds kill switch layer 2: a firewall rule that blocks `qbittorrent.exe` outbound on Ethernet and Wi-Fi
   - turns off any inbound rule Windows made for `qbittorrent.exe` at step 3
7. The output should say `qBittorrent: Running, runs as NT SERVICE\qBittorrent` and `qBittorrent is bound to nord-wg`.
8. From the Mac, open `http://<server-ip>:8080` and log in.

## 4. Kill-switch test

Don't download anything real until all of this passes. If any check fails, stop and write a roadblock.

The test file is Debian's netinst image, from Debian's own torrent page. It's under 1 GB and arrives in under a minute at full speed, which is too fast to test with, so slow it down first.

The `nord-wg` adapter only exists while the tunnel runs, so qBittorrent only lists it then. The order below tests the binding on its own before the binding is changed, so it never has to be picked while the tunnel is down.

Run the SSH commands from a `.ps1` file: through `ssh '...'`, the `$` in `WireGuardTunnel$nord-wg` gets lost. qBittorrent creates the file at full size at the start (a sparse file), so its size in Explorer doesn't show progress. Watch the web page's speed instead.

1. In the web page, **Options → Speed**: global download limit `500` KiB/s. Then **Add torrent link**: the `.iso.torrent` link for **amd64 netinst** from <https://cdimage.debian.org/debian-cd/current/amd64/bt-cd/>.
2. **Normal case.** Over SSH, list where qBittorrent's connections come from:
   ```powershell
   $q = (Get-Process qbittorrent).Id
   Get-NetTCPConnection -OwningProcess $q -State Established | Group-Object LocalAddress | Select-Object Count, Name
   Get-NetUDPEndpoint -OwningProcess $q | Select-Object LocalAddress, LocalPort
   ```
   Every peer connection and UDP port should be on the tunnel's address. Other than that, expect only the web page (local port 8080) and a pair of `127.0.0.1` connections that qBittorrent makes to itself.
3. **Tunnel down, both layers on.**
   ```powershell
   Stop-Service 'WireGuardTunnel$nord-wg'
   ```
   Within a minute the download speed should drop to 0, and the commands from 2 should show no peer connections and no UDP ports. The web page must still work from the Mac.
4. **Layer 1 alone.** With the tunnel still down, turn off the firewall rule:
   ```powershell
   Disable-NetFirewallRule -Name homeserver-qBittorrent-KillSwitch-Out
   ```
   The download must stay at 0 for a minute: only the binding is stopping it now. Turn the rule back on:
   ```powershell
   Enable-NetFirewallRule -Name homeserver-qBittorrent-KillSwitch-Out
   ```
5. **Layer 2 alone.** With the tunnel still down, set **Options → Advanced → Network interface** to **Any interface** in the web page. qBittorrent now listens on the Ethernet address, and the download must stay at 0: only the firewall rule is stopping it.
6. **Tunnel back.**
   ```powershell
   Start-Service 'WireGuardTunnel$nord-wg'
   ```
   Reload the web page and set **Network interface** back to **nord-wg**. The download should resume within a minute, with every connection on the tunnel again.
7. Set the download limit back to `0`, and delete the torrent and its files in the web page.

## 5. Prowlarr

**At the laptop:** install Prowlarr from <https://prowlarr.com/#downloads-v1-windows>. Keep **Install Windows Service** ticked.

**Over SSH:** run `setup-arr-services.ps1` again. It should report `Prowlarr: Running, runs as NT SERVICE\Prowlarr`.

At the end, the installer also starts Prowlarr at the desktop. That copy finds the service already running, opens the browser and quits. Its log shows `Another instance of Prowlarr is already running` and a `Fatal` startup line, which is expected. Under the virtual account, every start logs `Couldn't set permission for C:\ProgramData\Prowlarr ... WorldSid`: Prowlarr tries to give Everyone Modify on its folder, and its account isn't allowed to change permissions. Leave it that way.

The installer gives every user account Modify on `C:\ProgramData\Prowlarr`, including `bin`, the program the service runs. The script takes that away, and the same goes for every app's config folder: only SYSTEM, Administrators and the app's own account keep access. At the laptop, Explorer then asks for admin approval to open these folders. Click **Cancel**, not **Continue**: Continue adds your account to the folder for good.

**In the Mac's browser,** `http://<server-ip>:9696`:
1. Create the login: **Forms**, **Authentication Required: Enabled**, your username and a strong password.
2. **Settings → General → Backups**: interval **1** day, retention **7** days.
3. **Indexers → Add Indexer → Internet Archive.** It's the only source. Keep the defaults (Redirect off, Sync Profile Standard, Seed Ratio empty so qBittorrent's limit applies, no tags), except:
   - **Download using .torrent only. No Magnets.**: **On**. The Archive's `.torrent` files list archive.org's servers as web seeds, and many items have few other peers. A magnet link doesn't carry them.

   Test, then save. If the test fails with an SSL or connection error, open `https://archive.org` from the Mac: when archive.org itself is down, it fails there too.

The apps (Radarr, Sonarr) get added to Prowlarr in steps 6 and 7.

## 6. Radarr (movies)

**At the laptop:** install Radarr from <https://radarr.video/#downloads-v3-windows>, with **Install Windows Service**.

**Over SSH:** `setup-arr-services.ps1` again. Check `Radarr: Running, runs as NT SERVICE\Radarr`, and that `NT SERVICE\Radarr` has `(M)` on `D:\data\media`. The log in `C:\ProgramData\Radarr\logs` gets the same `WorldSid` warning as Prowlarr on every start.

**In the Mac's browser,** `http://<server-ip>:7878`:
1. Login: **Forms**, **Enabled**, strong password.
2. **Settings → Media Management** (Show Advanced):
   - Root folder: `D:\data\media\movies`
   - **Rename Movies: on**
   - **Use Hardlinks instead of Copy: on** (the default)
   - **Minimum Free Space: 51200** MB. Radarr won't import anything that would leave less than 50 GB free.
3. **Quality profiles:** nothing to change in **Settings → Profiles**, and don't delete any. Radarr has no global default. You pick the profile in the Add Movie dialog, and the browser remembers the last pick. Pick **HD-1080p** the first time. **Ultra-HD** is the 4K profile, picked per movie only when it's for the LG ([ADR 004](decisions/004-4k-direct-play-only.md)).
4. **Settings → Download Clients → + → qBittorrent**: host `localhost`, port `8080`, the qBittorrent username and password, category `movies`. Test, save.
5. **Settings → General → Backups**: interval **1** day, retention **7** days.
6. **Settings → General**: copy the **API Key**.
7. In Prowlarr: **Settings → Apps → + → Radarr**. Prowlarr server `http://localhost:9696`, Radarr server `http://localhost:7878`, the API key. Test, save. Prowlarr then adds Internet Archive to Radarr by itself.

## 7. Sonarr (TV)

**At the laptop:** install Sonarr v4 from <https://sonarr.tv/#downloads-v4-windows>. The installer's default is a tray app that starts at sign-in. Pick **Install Windows Service** instead.

**Over SSH:** `setup-arr-services.ps1` again. Check `Sonarr: Running, runs as NT SERVICE\Sonarr`.

**In the Mac's browser,** `http://<server-ip>:8989`: the same as Radarr, with:
- root folder `D:\data\media\tv`, **Rename Episodes: on**, hardlinks on, minimum free space 51200 MB
- quality profile **HD-1080p** in the Add Series dialog (no global default, same as Radarr)
- qBittorrent category `tv`
- backups daily, keep 7
- in Prowlarr, **Settings → Apps → + → Sonarr** with `http://localhost:8989` and Sonarr's API key

## 8. Bazarr (subtitles)

**At the laptop:**
1. Create a free account at <https://www.opensubtitles.com>. It's a different site from the old opensubtitles.org. Save the password in the password manager.
2. Download the Windows installer from <https://www.bazarr.media/#download> and run it. It asks only for the install folder: type `C:\ProgramData\Bazarr\bin`, so its account can update it without admin rights.

The installer doesn't ask about a service. It creates one called `Bazarr` on Local System, run by its own copy of NSSM in `bin`. Bazarr's settings, database, logs and backups go one level up, in `C:\ProgramData\Bazarr`. The installer also adds an inbound firewall rule named `Bazarr` for its `python.exe`, which allows any port from any address on every profile.

**Over SSH:** `setup-arr-services.ps1` again. Check `Bazarr: Running, runs as NT SERVICE\Bazarr` and `Disabled inbound rule: Bazarr`. NSSM reports Running even when the program it starts has crashed, so also check that `http://<server-ip>:6767` loads.

**In the Mac's browser,** `http://<server-ip>:6767`:
1. **Settings → General → Security**: authentication **Form**, username and strong password.
2. **Settings → General → Backup**: frequency **Daily**, retention **7** days.
3. **Settings → Languages**: add **English** and **Portuguese (Brazil)**. Create a languages profile with both, forced subtitles **off**. Make it the default for series and movies.
4. **Settings → Providers → OpenSubtitles.com**: the account from step 1.
5. **Settings → Library**, tabs **Sonarr** and **Radarr** (Bazarr 1.6): **Enabled** on, address `localhost`, ports `8989` and `7878`, Base URL empty, SSL off, each app's API key. Test, save. No path mappings: everything is on the same machine. Leave **Settings → Integrations** alone. It's for Plex and Jellyfin, not Sonarr or Radarr.
6. **Settings → Subtitles**: keep **Subtitle Folder: AlongSide Media File**, so Jellyfin finds them next to the video.

## 9. End-to-end test

1. In Radarr, add a public-domain film from Internet Archive and start a search. Keep its name out of the repo.
2. Watch it go through: qBittorrent downloads it into `torrents\incomplete`, moves it to `torrents\completed\movies`, then Radarr imports it into `movies\<Title (Year)>`.
3. Check the import made a hardlink, not a copy:
   ```powershell
   fsutil hardlink list "D:\data\media\movies\<folder>\<file>"
   ```
   It should list two names: one under `torrents\completed\movies` and one under `movies`.
4. Bazarr should fetch subtitles within a few minutes (**Movies** page). The `.srt` files appear next to the video.
5. In Jellyfin, the film shows up in Movies (or after **Scan All Libraries**). Play it on a TV and turn the subtitles on.

## 10. Nightly backup and VPN check

The apps' own backups run daily from steps 5 to 8. This task collects them every night.

**Over SSH:**

1. ```powershell
   powershell -ExecutionPolicy Bypass -File .\backup-arr-config.ps1 -Register
   ```
   Every day at 03:35, [`backup-arr-config.ps1`](../scripts/windows/backup-arr-config.ps1):
   - copies the newest backup zip of Sonarr, Radarr, Prowlarr and Bazarr. These are made while the apps run, in a way that's safe for their databases.
   - stops qBittorrent for a few seconds to copy its settings and resume files
   - zips them into `C:\ProgramData\homeserver\backup\arr-config-<date>.zip`
   - writes `status.txt` with a `VPN:` line (tunnel running, handshake under 5 minutes old, and Nord's check says the traffic is protected) and a `Backups:` line
2. Test it: `Start-ScheduledTask homeserver-arr-backup`, then `Get-Content C:\ProgramData\homeserver\backup\status.txt`. Expect `VPN: up` and `Backups: ok`. A new app may say it has no backup yet. Run its backup by hand once (**System → Backup → Backup Now**), then run the task again.

**On the Mac:**

3. `./scripts/mac/pull-config-backup.sh`. The log should show the Jellyfin lines as before, then `pulled arr-config-...zip`, `VPN: up`, `Backups: ok` and `Apps: all answered`. A `VPN: DOWN`, a backup problem or an app that doesn't answer shows a macOS notification.

The launchd job from Phase 2 runs the same script, so nothing else changes on the Mac.

## 11. Reboot test

1. From the Mac: `ssh homeserver Restart-Computer -Force`.
2. Wait two minutes without signing in at the laptop.
3. ```powershell
   Get-Service sshd, JellyfinServer, 'WireGuardTunnel$nord-wg', qBittorrent, Prowlarr, Radarr, Sonarr, *bazarr* |
       ForEach-Object { '{0} {1}' -f $_.Name, $_.Status }
   ```
   All should be Running.
4. On the Mac, run `pull-config-backup.sh` again: `Apps: all answered`.
5. Run the scheduled task again (step 10.2) and check `VPN: up`.

## Upkeep

- **Sonarr, Radarr, Prowlarr, Bazarr** update themselves. Their updaters keep the service account.
- **Re-running any of their installers** puts the service back on LocalService or Local System. Run `setup-arr-services.ps1` afterwards.
- **qBittorrent**, once a month over SSH:
  ```powershell
  winget upgrade qBittorrent.qBittorrent
  ```
  The service, its account and its settings stay. Check the web page afterwards.
- **WireGuard** updates itself while the tunnel service runs.

## Phase 3 done

- [ ] NordVPN app removed; WireGuard tunnel service connects at boot; LAN still works
- [ ] qBittorrent runs as `NT SERVICE\qBittorrent`, bound to `nord-wg`
- [ ] Kill-switch test passed (tunnel down, then each layer on its own)
- [ ] Prowlarr with Internet Archive only
- [ ] Radarr and Sonarr: hardlinks, 1080p default, 50 GB floor, qBittorrent connected
- [ ] Bazarr: English + Brazilian Portuguese from OpenSubtitles.com
- [ ] Every web page needs a login; all are LAN-only
- [ ] End-to-end: one item searched, downloaded, hardlinked, subtitled, played on a TV
- [ ] Nightly backup includes the Phase 3 apps; the Mac logs `VPN: up`
- [ ] Everything comes back after a reboot with nobody signed in
- [ ] Journal updated; roadblocks written up
