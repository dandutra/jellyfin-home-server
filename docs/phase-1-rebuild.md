# Phase 1: Clean rebuild

Goal: get from "old laptop I don't trust" to a clean, activated Windows 11 Pro install with up-to-date firmware, ready for Phase 2.

**Hardware:** Dell Latitude 3410, i5-10210U, 8 GB RAM, 256 GB NVMe.
**Done when:** Windows 11 Pro is activated, fully updated, drivers are installed, there's a local admin account, and the hostname is `homeserver`.

> Every time something goes wrong or surprises you, add a line to [`JOURNAL.md`](../JOURNAL.md). If it took more than a few minutes to solve, it also gets a file in [`docs/roadblocks/`](roadblocks/).
> Put command output with personal details (service tag, file names, IPs) in `local/`, which is gitignored, not in the repo.

## What you need

| Item | Notes |
|---|---|
| USB stick, 16–64 GB | Gets erased. The build script refuses anything bigger |
| Mac with free space | Receives the backup over SMB, so the external photo drive stays disconnected |
| Phillips #0 screwdriver, plastic pry tool | For the bottom cover |
| Air pump / compressor | Fan cleaning |
| 500 GB 2.5" 7 mm SATA SSD | Optional in this phase (see step 6) |
| Dell SATA cable 07CR4F + bracket | Only if the 2.5" bay is empty |

The new SSD is **not required for Phase 1**. Windows goes on the existing NVMe drive. The SSD becomes `D:` (media) and is first needed when we add a Jellyfin library in Phase 2. If the cable has to come from AliExpress, do Phase 1 without it and open the case a second time when it arrives.

---

## 1. Pre-wipe checks (on the laptop)

1. Download [`scripts/windows/pre-wipe-checks.ps1`](../scripts/windows/pre-wipe-checks.ps1) from GitHub (open it, then use the **Download raw file** button).
2. Open PowerShell **as Administrator** in the download folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\pre-wipe-checks.ps1
   ```
3. Paste the output to Claude, **but remove the service tag line first**.
4. Things to check in the output:
   - **License status** says `Licensed`.
   - **Firmware key** should say `present (... Professional OEM ...)`. Setup then picks Pro by itself. If it says `none`, you must **choose Windows 11 Pro by hand** in step 8.
   - **Storage controllers:** if you see "Intel RST" or "RAID", the BIOS is in RAID On mode. We change that in step 7.
   - **User folders:** add up the sizes to see how much the backup needs. If Desktop/Documents are tiny but `OneDrive` is big, Windows has moved those folders into OneDrive.
5. Your wife signs in at <https://account.microsoft.com/devices> and confirms the laptop is listed. That's the fallback route if activation fails after the reinstall.
6. Compare **BIOS version** in the output with the latest one for the Latitude 3410 at <https://www.dell.com/support> (enter the service tag → Drivers & Downloads → BIOS). If Dell has a newer one, download the `.exe` to the **Mac**, not the laptop. If it's already the latest, skip step 5.

## 2. Backup to the Mac over the network

The backup goes to a shared folder on the Mac, not to a USB drive. That way the external photo drive never gets plugged into this laptop. The Mac needs free space for the backup (about 15 GB here, less after the excluded files).

**On the laptop:**

1. **Antivirus scan before copying anything off.** Use the antivirus that's already active on the laptop:
   - **Kaspersky (or another third-party antivirus):** run a **Full Scan** from its own app. While it's installed, Defender is switched to passive mode and its Offline scan may be greyed out. Don't install a second antivirus next to it, because two real-time scanners fight over the same files.
   - **Defender only:** Windows Security → Virus & threat protection → Scan options → *Microsoft Defender Antivirus (offline scan)* → Scan now.

   Write the result in the journal (number of threats found, no file names).

**On the Mac:**

2. Create the destination folder: `mkdir ~/laptop-backup`.
3. System Settings → General → Sharing → turn on **File Sharing**, then click ⓘ:
   - **Shared Folders:** add `~/laptop-backup`, with your user set to *Read & Write*.
   - **Options…:** tick **Share files and folders using SMB**, and tick your user under *Windows File Sharing*. It asks for your Mac password.
4. Note the Mac's IP address: `ipconfig getifaddr en0`.

**On the laptop, in PowerShell as Administrator:**

5. Connect to the share. Replace the IP and user with yours; it asks for the Mac password:
   ```powershell
   net use \\<mac-ip>\laptop-backup /user:<mac-username>
   ```
   > Use the `\\ip\share` path, **not** a drive letter mapped in File Explorer. Windows hides drives mapped in a normal window from elevated (Administrator) windows, and the script needs Administrator to read both profiles.
6. Run the backup:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\backup-user-files.ps1 -Destination \\<mac-ip>\laptop-backup
   ```
   - Add `-IncludeOneDrive` only if some OneDrive files are not actually synced to the cloud.
   - Executables, scripts, shortcuts and macro-enabled Office files are skipped on purpose.
7. Copy over anything the script doesn't cover into the same `laptop-backup-YYYY-MM` folder.
8. Browsers: make sure sync is on (Chrome/Edge account), or export bookmarks and passwords to the backup folder.
9. Disconnect: `net use \\<mac-ip>\laptop-backup /delete`.

**On the Mac:** turn **File Sharing off** again once the copy is done.

## 3. Scan the backup (on the Mac)

```bash
brew install clamav
./scripts/mac/scan-backup.sh ~/laptop-backup
```

- **Exit 0** means clean. **Exit 1** means infected files were found: delete the files it names before restoring anything. **Exit 2** means clamscan had an error or scanned 0 files. Don't treat that as clean.
- Copy the summary lines (counts only) into the journal.

**Any external drive that was ever connected to the laptop** gets the same scan. Here that's the photo drive:

```bash
ls /Volumes                     # find the drive's name
caffeinate -i ./scripts/mac/scan-backup.sh "/Volumes/<DriveName>"
```

- macOS mounts NTFS drives read-only, which is fine for a scan. Allow Terminal access to removable volumes if macOS asks.
- `caffeinate` keeps the Mac awake. Keep the lid open and the charger connected: a large drive takes hours.
- The script lists suspicious files at the top level of the drive (`autorun.inf`, `.exe`, `.lnk`...). Check their dates before you panic: drives often ship with the maker's own setup files.

## 4. Build the install USB (on the Mac)

1. Download the Windows 11 **multi-edition ISO** (x64) from <https://www.microsoft.com/software-download/windows11>. On a Mac the page offers the ISO directly.
   - **Language:** English (United States) makes error messages easier to search for and the screenshots more useful for the portfolio. Your wife's account can add Portuguese as its display language later.
2. Install wimlib and find the stick's disk id:
   ```bash
   brew install wimlib
   diskutil list external
   ```
   Find the line with the stick's size (~16 GB) and note its id, e.g. `disk4`. **Disconnect any other external drive first**, so it can't be picked by mistake.
3. Build the stick:
   ```bash
   ./scripts/mac/build-usb.sh ~/Downloads/<windows-iso>.iso disk4 ~/Downloads/Latitude_3410_*.exe
   ```
   Use the ISO's exact file name (Microsoft changes the naming between releases). Leave out the last argument if the BIOS is already up to date.
   The script:
   - refuses internal disks and anything bigger than 64 GB
   - makes you type the disk id to confirm
   - formats the stick FAT32 + GPT
   - copies the installer
   - splits `install.wim` with wimlib
   - copies the BIOS `.exe` onto the stick, if given
   - lists the editions in the image

   > **Why the split:** UEFI firmware boots reliably only from FAT32. FAT32 can't hold a file over 4 GiB, and `install.wim` is bigger than that. Windows Setup accepts a split `install.swm` with no extra steps.

## 5. Update the BIOS (on the laptop)

Skip this step if step 1.6 showed the BIOS is already the latest version.


1. Plug the laptop into **AC power** (the BIOS update refuses to run on battery alone) and insert the stick.
2. Restart and tap **F12** at the Dell logo → **BIOS Flash Update** → choose the `.exe` on the stick → confirm.
3. **Don't unplug anything until it reboots by itself.**

> **Why from F12 and not from Windows:** the update runs from the firmware itself, so the Windows install we don't trust never touches it.

## 6. Open the case

1. **Power off fully** (Shift + Shut down). Remove the bottom cover: loosen the captive screws, then pry it off starting at the hinge corners.
2. **Disconnect the battery cable first**, before touching anything else.
3. Check the battery for swelling. Take photos.
4. Clean the fan and heatsink with the pump. **Hold the fan still** so it doesn't over-spin while you blow air through it.
5. **2.5" bay:** is there a bracket and a flat cable going to the motherboard?
   - **Yes:** fit the SSD into the bracket, connect it, screw it in.
   - **No:** note it, then order cable 07CR4F + bracket. The SSD goes in later. This doesn't block anything until Phase 2's library step.
6. Reconnect the battery, close the cover.

Take photos of each step for `docs/img/`. Make sure no stickers with the service tag or serial are visible.

## 7. BIOS settings

Tap **F2** at the Dell logo. Menu names vary slightly between BIOS versions:

| Setting | Where (approx.) | Value | Why |
|---|---|---|---|
| SATA/NVMe Operation | System Configuration / Storage | **AHCI** | In RAID On, Windows Setup shows no drives |
| Secure Boot | Secure Boot | **Enabled** | Blocks unsigned bootloaders and bootkits |
| Primary Battery Charge Configuration | Power Management | **Primarily AC Use** | The battery is at 16% health and stays plugged in |
| AC Behavior / Wake on AC | Power Management | **Enabled** | Boots back up after a power cut |
| Admin (setup) password | Security | Optional: set it, store it in a password manager | Stops anyone from changing boot settings |

Apply, exit.

> Switching to AHCI on an **existing** Windows install makes it fail to boot. That doesn't matter here, because we wipe the drive in the next step.

## 8. Clean install

1. Restart, tap **F12** → select the **UEFI** USB entry.
2. Language/keyboard → **Install now**.
3. Product key → **I don't have a product key**.
4. Edition: with the Pro key in firmware, Setup normally skips this screen. If it asks, choose **Windows 11 Pro**. ⚠️ Choosing Home installs and activates as Home.
5. **Custom install**. Delete **every partition** on the ~238 GB drive (Disk 0) until it shows only *Unallocated Space*. If the SSD is installed it appears as another disk (~465 GB). **Don't touch it.**
6. Select the unallocated space → Next.
7. **Setup screens (OOBE):** region, keyboard, network. Keep Ethernet unplugged and skip Wi-Fi. The local-account options below work best offline.
8. **Local account:** when it asks for a Microsoft account, try these in order:
   1. **Sign-in options → Domain join instead** (if shown), then enter a local admin username.
   2. Press **Shift + F10** to open a command prompt, then run `start ms-cxh:localonly`. A local-account dialog opens.
   3. If neither works on this Windows build, **stop**: log it as a roadblock. We'll build an `autounattend.xml` that creates the local account.

   Use a **strong password** and save it in a password manager.
9. Privacy screens: choose **No** for everything optional.

## 9. Post-install

1. **Activation:** Settings → System → Activation should show *Active, digital license*. If not, the fallback is to add your wife's Microsoft account (next step) and run the **Troubleshoot** button on that page while signed in as her.
2. **Windows Update:** run it repeatedly until nothing is left, including optional driver updates.
3. **Drivers:** install **Dell Command | Update** from Dell's site and apply everything. This brings in the Intel graphics driver, which Quick Sync needs in Phase 2.
4. **Hostname:** in an admin PowerShell, run `Rename-Computer -NewName homeserver -Restart`.
5. **Your wife's account:** Settings → Accounts → Other users → Add account → her Microsoft account. Leave it as a **Standard user**.
6. **SSD, if installed:** Disk Management → initialize as **GPT** → New Simple Volume → **NTFS**, letter **D:**, label `Media`.
7. **Restore files:** turn File Sharing back on on the Mac, open `\\<mac-ip>\laptop-backup` from each account, copy the scanned files back, then turn File Sharing off and delete the backup from the Mac:
   ```bash
   chflags -R nouchg ~/laptop-backup   # macOS may have locked folders that were Read-only on Windows
   rm -rf ~/laptop-backup
   ```
8. Run `pre-wipe-checks.ps1` again and keep the output in `local/` as a before/after record (Edition, License, Storage controllers should all show the new state).

## Phase 1 done ✅

- [ ] Windows 11 Pro, activated
- [ ] BIOS updated, AHCI, Secure Boot on, charge limit set
- [ ] All updates and Dell drivers installed
- [ ] Local admin account + wife's standard account
- [ ] Hostname `homeserver`
- [ ] SSD installed as `D:` (or cable ordered and noted in the journal)
- [ ] Journal updated; roadblocks written up
