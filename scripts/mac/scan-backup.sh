#!/usr/bin/env bash
# Scan the backup drive with ClamAV from macOS before anything is restored.
#
# Windows malware can't execute on macOS, so the Mac is a safe place to inspect
# files copied off a suspect Windows machine. Scans the whole volume (not just
# the backup folder) because the drive itself was attached to that machine.
#
# Usage: scan-backup.sh </Volumes/DriveName>
# Requires: brew install clamav
# Logs land in local/ (gitignored): they contain file names.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: $0 </Volumes/DriveName>"
TARGET="$1"
[[ -d "$TARGET" ]] || die "not a directory: $TARGET"
command -v clamscan >/dev/null || die "ClamAV not installed (brew install clamav)"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$REPO_ROOT/local"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/clamscan-$STAMP.log"

# Homebrew ships only a sample config; freshclam refuses to run without a real one.
ETC="$(brew --prefix)/etc/clamav"
if [[ ! -f "$ETC/freshclam.conf" ]]; then
  sed '/^Example/d' "$ETC/freshclam.conf.sample" >"$ETC/freshclam.conf"
fi

echo "Updating virus definitions..."
freshclam

echo "Looking for USB-worm droppings in the drive root..."
find "$TARGET" -maxdepth 1 \( -iname 'autorun.inf' -o -iname '*.lnk' -o -iname '*.exe' -o -iname '*.vbs' -o -iname '*.js' \) \
  | tee "$LOG_DIR/root-suspicious-$STAMP.txt"

echo "Scanning $TARGET (large drives take hours)..."
set +e
clamscan --recursive --infected --log="$LOG" "$TARGET"
status=$?
set -e

echo
case $status in
  0) echo "Clean: no infected files found." ;;
  1) echo "INFECTED FILES FOUND. Review $LOG and delete them before restoring anything." ;;
  *) echo "clamscan reported errors (exit $status). See $LOG." ;;
esac
echo "Summary for the journal (no file names):"
grep -E '^(Scanned files|Infected files|Data scanned|Time):' "$LOG" || true
exit "$status"
