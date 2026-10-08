#!/usr/bin/env bash
# Build a UEFI-bootable Windows 11 installer USB on macOS.
#
# FAT32 is the only filesystem UEFI firmware reliably boots, but it caps files
# at 4 GiB and the Windows 11 install.wim is larger. We copy everything else
# as-is and split install.wim into install.swm/install2.swm with wimlib;
# Windows Setup picks up split images automatically.
#
# Usage: build-usb.sh <path/to/Win11.iso> <diskN> [path/to/Dell-BIOS.exe]
# Requires: brew install wimlib

set -euo pipefail

MAX_STICK_BYTES=$((64 * 1000 * 1000 * 1000)) # refuse anything bigger than 64 GB
SPLIT_MB=3800
VOLUME_NAME="WIN11"

die() { echo "error: $*" >&2; exit 1; }

[[ $# -ge 2 && $# -le 3 ]] || die "usage: $0 <win11.iso> <diskN> [bios.exe]"
ISO="$1"
DISK="/dev/${2#/dev/}"
BIOS_EXE="${3:-}"

[[ -f "$ISO" ]] || die "ISO not found: $ISO"
[[ -z "$BIOS_EXE" || -f "$BIOS_EXE" ]] || die "BIOS file not found: $BIOS_EXE"
command -v wimlib-imagex >/dev/null || die "wimlib not installed (brew install wimlib)"
[[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || die "pass a whole disk like disk4, not a partition"

info="$(diskutil info -plist "$DISK")" || die "no such disk: $DISK"
internal="$(plutil -extract Internal raw - <<<"$info")"
size="$(plutil -extract TotalSize raw - <<<"$info")"
media="$(plutil -extract MediaName raw - <<<"$info" 2>/dev/null || echo unknown)"

[[ "$internal" == "false" ]] || die "$DISK is an internal disk, refusing"
(( size <= MAX_STICK_BYTES )) || die "$DISK is $((size / 1000000000)) GB; that is not a USB stick, refusing"

echo "About to ERASE $DISK ($media, $((size / 1000000000)) GB)."
diskutil list "$DISK"
read -r -p "Type the disk id (${DISK#/dev/}) to continue: " answer
[[ "$answer" == "${DISK#/dev/}" ]] || die "confirmation did not match, nothing changed"

diskutil eraseDisk FAT32 "$VOLUME_NAME" GPT "$DISK"
DST="/Volumes/$VOLUME_NAME"

SRC="$(hdiutil attach -nobrowse -readonly "$ISO" | awk -F'\t' '/\/Volumes\//{print $NF}')"
[[ -d "$SRC" ]] || die "could not mount ISO"
trap 'hdiutil detach "$SRC" >/dev/null 2>&1 || true' EXIT

echo "Copying installer files (except install.wim), this takes a few minutes..."
rsync -r --exclude=sources/install.wim "$SRC/" "$DST/"

if [[ -f "$SRC/sources/install.wim" ]]; then
  echo "Editions in this image (pick Windows 11 Pro during setup):"
  wimlib-imagex info "$SRC/sources/install.wim" | awk -F': *' '/^Name:/{print "  - " $2}'
  echo "Splitting install.wim into ${SPLIT_MB} MB parts..."
  wimlib-imagex split "$SRC/sources/install.wim" "$DST/sources/install.swm" "$SPLIT_MB"
fi

if [[ -n "$BIOS_EXE" ]]; then
  cp "$BIOS_EXE" "$DST/"
  echo "Copied BIOS update: $(basename "$BIOS_EXE")"
fi

sync
diskutil eject "$DISK"
echo "Done. The stick is ejected and ready."
