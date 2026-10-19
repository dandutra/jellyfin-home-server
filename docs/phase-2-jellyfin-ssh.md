# Phase 2: SSH + Jellyfin

Goal: manage the server from the Mac over SSH, and stream to the TVs from Jellyfin running as a low-privilege Windows service.

**Starts from:** Phase 1 done. Windows 11 Pro, updated, Dell drivers installed, `D:` is the media SSD.
**Done when:** the Mac logs in over SSH with a key (passwords refused), the server stays awake and restarts for updates only at 04:00, Jellyfin plays on both TVs with Quick Sync transcoding, and the Mac pulls a config backup every night.

> Same rules as Phase 1: anything surprising goes in [`JOURNAL.md`](../JOURNAL.md), anything that took a while goes in [`docs/roadblocks/`](roadblocks/), and output with IPs, MAC addresses or usernames goes in `local/`.

Steps 1 to 3 happen at the laptop. From step 4 on, everything runs from the Mac over SSH, except installing Jellyfin itself (step 7).

---

## 1. BIOS

1. Connect AC power.
2. Open the BIOS from Windows: **Settings → System → Recovery → Advanced startup: Restart now → Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**.
3. Use the search box:

| Search for | Setting | Value | Why |
|---|---|---|---|
| `SupportAssist` | SupportAssist OS Recovery | **Off** | After a failed boot, Dell's recovery screen waits for a network download instead of retrying Windows. That's what looped in [roadblock 003](roadblocks/003-boot-files-on-the-usb-stick.md) |
| `SupportAssist` | Auto OS Recovery Threshold | **Off** | Same reason |
| `Boot Sequence` | Boot Sequence | **Windows Boot Manager** first. Delete the old USB installer entry if the list still has it | The USB-first order from Phase 1 is no longer needed |
| `Wake on AC` | Wake on AC | **On** (check it's still set) | The server starts again by itself after a power cut |

4. **Apply Changes**, then **Exit**. Windows should start normally.

## 2. Network

The server gets the same IP address every time from the router (a *DHCP reservation*), so the Mac and the TVs can always find it. The laptop sometimes moves around the house, so we reserve an address for the Wi-Fi adapter too. Each adapter has its own hardware (MAC) address, so each gets its own IP.

1. Plug in the Ethernet cable.
2. In PowerShell, list the adapters:
   ```powershell
   Get-NetAdapter -Physical | Format-Table Name, InterfaceDescription, MacAddress, Status
   ```
   Note the MAC address of the Ethernet and the Wi-Fi adapter. Keep them in `local/`, not in the repo.
3. On the router's admin page, find **DHCP reservation** (some routers call it *Address reservation* or *Static lease*). Add one entry per MAC address. Note both IPs in `local/`.
4. Restart the laptop so it picks up the reserved addresses, then check with `ipconfig`.
5. Set both networks to **Private**. On a Public network the SSH and Jellyfin firewall rules don't apply. In an admin PowerShell:
   ```powershell
   Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
   Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
   ```
   This changes only the networks connected right now. If the Wi-Fi isn't connected at the moment, run it again the next time it is.

## 3. SSH

You log in with a *key pair* instead of a password. The private half stays on the Mac and never leaves it. The public half goes on the server. A key can't be guessed the way a password can, so once keys work we turn passwords off. Background in [ADR 005](decisions/005-ssh-lan-only-no-rdp.md).

**On the Mac:**

1. Create a key just for this server:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/homeserver_ed25519 -C "mac-to-homeserver"
   ```
   Give it a passphrase and save the passphrase in your password manager. The passphrase protects the key if someone copies it off the Mac.
2. Store the passphrase in the macOS Keychain, so you (and the nightly backup job) don't have to type it:
   ```bash
   ssh-add --apple-use-keychain ~/.ssh/homeserver_ed25519
   ```
3. Add the server to `~/.ssh/config`. Use the Ethernet IP from step 2 and the server's admin username:
   ```
   Host homeserver
     HostName 192.0.2.10
     User <admin-username>
     IdentityFile ~/.ssh/homeserver_ed25519
     IdentitiesOnly yes
     UseKeychain yes
     AddKeysToAgent yes
   ```
4. Copy the **public** key (the `.pub` file) to the USB stick from Phase 1:
   ```bash
   cp ~/.ssh/homeserver_ed25519.pub /Volumes/<stick-name>/
   ```
   It's safe to carry around: it can only check a login, not make one.

**On the laptop:**

5. Insert the stick. Download [`scripts/windows/setup-ssh.ps1`](../scripts/windows/setup-ssh.ps1) from GitHub (**Download raw file**).
6. In an admin PowerShell in the download folder, run it with the stick's drive letter:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-ssh.ps1 -PublicKeyPath E:\homeserver_ed25519.pub
   ```
   It installs OpenSSH Server, adds the key, turns passwords off, opens port 22 to the home network only and makes PowerShell the login shell. It doesn't touch user accounts or other firewall rules.
7. The last line is the server's **host key fingerprint** (`SHA256:...`). Take a photo of it.

**On the Mac:**

8. Connect:
   ```bash
   ssh homeserver
   ```
   The first time, ssh shows a fingerprint and asks whether to trust it. It must match the photo from step 7. If it doesn't, answer **no**: something else on the network answered.
9. Check that passwords are refused:
   ```bash
   ssh -o PubkeyAuthentication=no homeserver
   ```
   This must fail with `Permission denied (publickey)` without asking for a password.
   > The first run of the script left `keyboard-interactive` on the list of login methods. On Windows it never asks for a password, because nothing on Windows answers it, but the script now turns it off too so the config states what we mean.

From here on, Claude runs the commands over SSH. The steps below still show them, so you can run them yourself.

## 4. Look at the `WsiAccount` profile

A profile named `WsiAccount` appeared after the install, and nobody created it. To see what it is (read-only):

```powershell
Get-LocalUser | Format-Table Name, Enabled, Description, LastLogon
Get-CimInstance Win32_UserProfile | Where-Object LocalPath -like '*Wsi*' |
    Format-List LocalPath, SID, Special, Loaded, LastUseTime
```

**What it turned out to be:** a **disabled** local account that Windows created itself. Its description reads *"A user account managed and used by the system for Web Sign-in scenarios."* It sits in the same list as `DefaultAccount` and `WDAGUtilityAccount`, which Windows also manages. Its folder holds a default profile (about 600 small files), not personal data.

**Leave it alone.** A disabled account can't sign in, locally or over SSH, and deleting an account Windows manages can break the feature that uses it.

## 5. Power and updates

```powershell
powershell -ExecutionPolicy Bypass -File .\set-power-and-updates.ps1
```

[`set-power-and-updates.ps1`](../scripts/windows/set-power-and-updates.ps1) changes these settings, for AC power only:
- The laptop never sleeps or hibernates, and never powers down the disks. The screen turns off after 5 minutes.
- Closing the lid does nothing.
- Hibernation is off. That also turns off Fast Startup, so F2/F12 at the Dell logo work again.
- Windows Update installs automatically every day at 04:00 and restarts if it needs to. Active hours are 05:00–23:00, so it never restarts during the day.

Until this step runs, the laptop still sleeps on its default timer, and SSH just times out (`Connection timed out during banner exchange`). Wake it at the keyboard first.

To check it worked, the script prints the AC sleep timeout and the lid action, both `0x00000000`. The lid action is a hidden setting: `powercfg /query` prints nothing for it, only `powercfg /qh` does. `powercfg /a` should list Hibernate as *not enabled*. The laptop uses Modern Standby (S0), so S3 sleep doesn't exist on it anyway.

## 6. Media folders and test files

1. Make the folders for the test files. Step 8 creates the rest of the tree from [ADR 007](decisions/007-config-and-media-layout.md):
   ```powershell
   New-Item -ItemType Directory -Force 'D:\data\media\movies\Big Buck Bunny (2008)', 'D:\data\media\movies\Jellyfin test 4K HEVC'
   ```
2. Download test files that are free to use. Turning off the progress bar makes `Invoke-WebRequest` on PowerShell 5.1 many times faster:
   - *Big Buck Bunny* (2008, Blender Foundation, CC BY 3.0), 1080p H.264. Blender serves it only as a zip (725 MB, a 692 MB `.mov` inside):
     ```powershell
     $ProgressPreference = 'SilentlyContinue'
     $bbb = 'D:\data\media\movies\Big Buck Bunny (2008)'
     Invoke-WebRequest -UseBasicParsing 'https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_1080p_h264.mov.zip' -OutFile "$bbb\bbb.zip"
     Expand-Archive "$bbb\bbb.zip" -DestinationPath $bbb
     Remove-Item "$bbb\bbb.zip"
     ```
   - `Test Jellyfin 4K HEVC 10bit 40M.mp4` (141 MB) from Jellyfin's own test set at <https://repo.jellyfin.org/test-videos/> (CC BY-SA 4.0). It tests direct play on the LG and Quick Sync on everything else. It's the lowest bitrate of the 4K 10-bit clips, which is enough for both tests. Check it against the published SHA-256:
     ```powershell
     $hevc = 'D:\data\media\movies\Jellyfin test 4K HEVC'
     $url  = 'https://repo.jellyfin.org/test-videos/SDR/HEVC%2010bit/Test%20Jellyfin%204K%20HEVC%2010bit%2040M.mp4'
     Invoke-WebRequest -UseBasicParsing $url -OutFile "$hevc\Test Jellyfin 4K HEVC 10bit 40M.mp4"
     $sum = Invoke-WebRequest -UseBasicParsing "$url.sha256sum"
     $expected = ([Text.Encoding]::ASCII.GetString($sum.Content) -split '\s+')[0]
     $expected -eq (Get-FileHash "$hevc\Test Jellyfin 4K HEVC 10bit 40M.mp4").Hash   # True
     ```
     > The server sends `.sha256sum` as `application/octet-stream`, so PowerShell 5.1 returns `.Content` as bytes, not text. Splitting the bytes without decoding them first gave `False` on a good file.

## 7. Install Jellyfin (at the laptop)

The installer is graphical, so this step happens at the laptop.

1. Download the Windows installer from <https://jellyfin.org/downloads/windows>.
2. Run it and choose **Advanced**:
   - Tick **Install As a Service**.
   - Service account: **Use Network Service account (Recommended)**. Step 8 replaces it with Jellyfin's own account.
   - Data folder: keep the default, `C:\ProgramData\Jellyfin\Server`.
   - Keep **Start Service after Install** ticked.
3. Don't open the web page yet.

> On the first install, the installer said it couldn't start the service, but it had started. The first start takes over a minute (75 s here) while Jellyfin sets up its database and checks ffmpeg, and the installer most likely stops waiting before that. It keeps no log, so I couldn't confirm. To check: `Get-Service JellyfinServer` should say **Running**, and `http://localhost:8096/health` should answer `Healthy`. Later starts take a few seconds.

## 8. Jellyfin's own account and permissions (over SSH)

[ADR 006](decisions/006-service-accounts.md) has the background. In short, Jellyfin runs as `NT SERVICE\JellyfinServer`, an account Windows creates for this one service. It has no password and nobody can sign in with it. It can read the media but not change or delete it.

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-jellyfin-service.ps1
```

[`setup-jellyfin-service.ps1`](../scripts/windows/setup-jellyfin-service.ps1):
- creates `D:\data\media\{movies,tv,torrents\incomplete,torrents\completed}`
- switches the service to `NT SERVICE\JellyfinServer` and makes it restart after a crash
- limits `D:\data` to Administrators, SYSTEM and your admin account (full control), plus Jellyfin (read only)
- gives Jellyfin write access to its own data folder
- opens port 8096 (web and apps) and 7359 (apps finding the server by themselves) to the home network only

The output should say `runs as NT SERVICE\JellyfinServer` and `Running`. `D:\data` should list exactly four entries: `NT SERVICE\JellyfinServer:(OI)(CI)(RX)`, your admin account, SYSTEM and Administrators.

To check that Jellyfin works under the new account:
```powershell
Get-Process jellyfin -IncludeUserName | Select-Object UserName   # NT SERVICE\JellyfinServer
(Invoke-WebRequest -UseBasicParsing http://localhost:8096/health).Content   # Healthy
```
From the Mac, `curl http://<server-ip>:8096/health` should also say `Healthy`, which shows the firewall rule works.

> The first run failed at icacls with exit code 1332, *No mapping between account names and security IDs*. Over SSH, `$env:USERDOMAIN` is `WORKGROUP`, not the computer name. The script now names the admin account by its SID. See [roadblock 004](roadblocks/004-icacls-workgroup-over-ssh.md).

> ⚠️ **Run this script again after every Jellyfin upgrade.** The installer removes and re-creates the service, which puts it back on Network Service. The permissions stay, because Windows derives the account from the service name.

## 9. First-run setup (in the Mac's browser)

1. Open `http://<server-ip>:8096`.
2. Language, then the **admin** account: not your everyday name, with a strong password saved in your password manager.
3. Libraries:
   - **Movies** → `D:\data\media\movies`
   - **Shows** → `D:\data\media\tv`
4. Remote access screen:
   - **Allow remote connections to this server: on.** Despite the name, "remote" here means any device other than the server itself, so the TVs need it. The firewall rule still keeps everything outside the house out.
   - **Enable automatic port mapping: off.** This would ask the router to open a port to the internet.
5. Sign in, open **Dashboard → Libraries** and check that both test files show up.

## 10. Quick Sync transcoding

When a TV can't play a file as it is, Jellyfin converts it on the fly (*transcodes*). The CPU alone is too slow for 4K. Quick Sync is the video engine built into the Intel graphics, and it does the job with little CPU.

1. **Dashboard → Playback → Transcoding**:
   - Hardware acceleration: **Intel QuickSync (QSV)**
   - Hardware decoding: tick **H264, HEVC, MPEG2, VC1, VP8, VP9, HEVC 10bit, VP9 10bit**. Leave AV1 unticked, the UHD 620 can't decode it.
   - Tick **Enable hardware encoding**.
   - Tick **Enable tone mapping**, so 4K HDR looks right when converted to 1080p SDR for the Fire TV.
   - Save.
2. Test: play the 4K test clip in the Mac's browser and pick a lower quality (gear icon → Quality → 720p), so Jellyfin has to transcode.
3. **Dashboard → Activity**, or the playback info in the player, should show the transcode, and CPU use in Task Manager should stay low.
4. If playback fails, look at the newest `FFmpeg.Transcode-*.log` in `C:\ProgramData\Jellyfin\Server\log`. Quick Sync errors there under the service account are the expected trouble spot. Log them as a roadblock.

## 11. Users and clients

1. **Dashboard → Users**: one account per person. Not administrators, and **Allow media deletion** off.
2. **LG 43UT7000:** install *Jellyfin* from the LG Content Store. Server address `http://<server-ip>:8096`. Play the 4K test clip: it should **direct play**, with no transcode in Dashboard → Activity ([ADR 004](decisions/004-4k-direct-play-only.md)).
3. **Fire TV Stick:** install *Jellyfin* from the Amazon Appstore. Same server address. Play both test files. The 4K clip should transcode to 1080p with Quick Sync.

## 12. Nightly config backup

The configs (users, libraries, watch history) are small and take time to recreate. The media isn't backed up: it's watched and then deleted.

**On the server (over SSH):**

1. Schedule the backup:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\backup-jellyfin-config.ps1 -Register
   ```
   Every day at 03:30, [`backup-jellyfin-config.ps1`](../scripts/windows/backup-jellyfin-config.ps1) stops Jellyfin for under a minute, zips its configs into `C:\ProgramData\homeserver\backup` (cache, transcodes, trickplay and logs are left out) and starts it again. Only Administrators and SYSTEM can read that folder, because the zip holds password hashes and API keys.
2. Run it once by hand to test: `Start-ScheduledTask homeserver-config-backup`, then check that a zip appears.

**On the Mac:**

3. Pull it once by hand:
   ```bash
   ./scripts/mac/pull-config-backup.sh
   ```
   It copies the newest zip to `~/homeserver-backups`, keeps the last 7 and checks that Jellyfin answers on port 8096. A failure shows a macOS notification.
4. Schedule it:
   ```bash
   ./scripts/mac/pull-config-backup.sh --install
   ```
   launchd runs it daily at 03:50, or when the Mac wakes up if it was asleep at that time. The log is in `~/Library/Logs/homeserver-backup.log`.

## 13. Reboot test

1. From the Mac: `ssh homeserver Restart-Computer -Force`.
2. Wait two minutes without signing in at the laptop.
3. `ssh homeserver "Get-Service sshd, JellyfinServer"`: both should be **Running**. Both start at boot, before anyone signs in.
4. Play something on one of the TVs.

## Phase 2 done

- [x] BIOS: SupportAssist OS Recovery off, Windows Boot Manager first
- [x] Ethernet with DHCP reservations for both adapters; networks Private
- [x] SSH from the Mac with a key; passwords refused
- [x] `WsiAccount` identified and noted in the journal
- [x] No sleep on AC, lid does nothing, updates restart at 04:00
- [x] Jellyfin running as `NT SERVICE\JellyfinServer`, read-only on media
- [ ] Quick Sync transcoding works
- [ ] LG direct plays 4K; Fire TV plays with transcoding
- [ ] Nightly config backup lands on the Mac
- [ ] Services come back after a reboot with nobody signed in
- [ ] Journal updated; roadblocks written up
