# 003: Windows put its boot files on the USB stick

**Phase:** 1 · **Date:** 2026-10-17 · **Time lost:** ~2h

## Problem
The clean install finished and Windows ran fine for a day. Then I forced a power-off during a slow sign-in, with the USB stick already removed. On the next start, the laptop didn't find Windows. Dell's SupportAssist ran a hardware scan ("Success"), said it would download its recovery environment (cSOS), and asked for Ethernet. Without a cable it ran the same scan again in a loop.

In the BIOS, the boot sequence listed only `Onboard NIC (IPV4)` and `Onboard NIC (IPV6)`. Both drives showed up in the BIOS, and SATA was still set to AHCI.

## What I tried
1. Tried to add a boot entry for `\EFI\Microsoft\Boot\bootmgfw.efi` by hand. The BIOS file browser offered no file system on either internal drive, only the network entries. So neither drive had an EFI System Partition.
2. Put the stick back in and added a boot entry for its `\EFI\Boot\bootx64.efi`, expecting Windows Setup to open its repair tools. Instead the laptop booted the **installed** Windows.
3. From Windows, `bcdedit /enum firmware` showed that **Windows Boot Manager** and the USB entries all pointed to the same volume, which was on the stick. The NVMe had only MSR, C: and Recovery partitions.

## Root cause
On a GPT disk, `diskutil eraseDisk` always adds a 200 MB EFI System Partition. My USB script formatted the stick as GPT, so the stick had one. Windows Setup found an existing EFI System Partition and put the installed system's boot files there, instead of creating one on the NVMe. The laptop booted only while the stick was in. Until I removed it, nothing showed the problem.

## Fix
Gave the NVMe its own EFI partition and boot files from the running Windows:

```
diskpart
select volume C
shrink desired=300 minimum=300
create partition efi size=260
format quick fs=fat32 label="System"
assign letter=S
exit
bcdboot C:\Windows /s S: /f UEFI
```

After that, the laptop booted from the NVMe with the stick removed. `build-usb.sh` now formats the stick as MBR, which gets no EFI partition, and UEFI still boots it.

## What I learned
An install isn't done until it boots with the install media removed. I now test that before calling a step finished. I also learned to read a tool's defaults: "GPT" on macOS quietly means "GPT plus an EFI partition", and Windows Setup trusts whatever EFI partition it finds first.
