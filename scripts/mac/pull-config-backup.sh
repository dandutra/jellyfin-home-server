#!/usr/bin/env bash
# Pull the newest config zips from the server over SSH (Jellyfin, and the Phase 3
# apps once they're installed), keep the last 7 of each, log the server's VPN
# status, and check that the apps answer. Runs nightly from launchd.
#
# Usage: pull-config-backup.sh            pull now
#        pull-config-backup.sh --install  add the launchd job (daily 03:50, or on wake if asleep)
# Needs a "homeserver" entry in ~/.ssh/config (see docs/phase-2-jellyfin-ssh.md).
# A failure shows a macOS notification and is logged to ~/Library/Logs/homeserver-backup.log.

set -euo pipefail

HOST="${HOMESERVER_SSH_HOST:-homeserver}"
DEST="${HOMESERVER_BACKUP_DIR:-$HOME/homeserver-backups}"
KEEP=7
REMOTE_DIR='C:/ProgramData/homeserver/backup'
LABEL="com.homeserver.config-pull"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
fail() {
  log "FAILED: $*"
  osascript -e "display notification \"$*\" with title \"homeserver backup failed\"" || true
  exit 1
}

if [[ "${1:-}" == "--install" ]]; then
  script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  plist="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$script</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>50</integer></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/homeserver-backup.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/homeserver-backup.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "Installed $plist. Run now with: launchctl kickstart gui/$(id -u)/$LABEL"
  exit 0
fi

mkdir -p "$DEST"
chmod 700 "$DEST"

# BatchMode: never wait for a password prompt when run from launchd.
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15)

# Pull the newest <prefix>-YYYYMMDD-HHMM.zip and keep the last $KEEP locally.
pull_latest() {
  local prefix="$1" latest
  # shellcheck disable=SC2029  # REMOTE_DIR and prefix are meant to expand here, on the Mac.
  latest="$(ssh "${ssh_opts[@]}" "$HOST" \
    "Get-ChildItem '$REMOTE_DIR' -Filter '$prefix-*.zip' | Sort-Object Name | Select-Object -Last 1 -ExpandProperty Name" |
    tr -d '\r')" || fail "ssh to $HOST failed"
  [[ "$latest" =~ ^$prefix-[0-9]{8}-[0-9]{4}\.zip$ ]] || fail "no $prefix zip found on $HOST"

  if [[ -f "$DEST/$latest" ]]; then
    log "already have $latest"
  else
    scp -q "${ssh_opts[@]}" "$HOST:$REMOTE_DIR/$latest" "$DEST/" || fail "scp of $latest failed"
    log "pulled $latest ($(du -h "$DEST/$latest" | cut -f1))"
  fi

  # Names sort by date, so the oldest come first.
  local zips=("$DEST/$prefix"-*.zip)
  if ((${#zips[@]} > KEEP)); then
    rm -f -- "${zips[@]:0:${#zips[@]}-KEEP}"
  fi
}

shopt -s nullglob
pull_latest jellyfin-config

# -T: without it, ssh -G warns about a pseudo-terminal when stdin isn't a terminal.
server="$(ssh -T -G "$HOST" | awk '/^hostname /{print $2}')"
health="$(curl -fsS --max-time 10 "http://$server:8096/health")" || fail "Jellyfin on $server:8096 did not answer"
[[ "$health" == "Healthy" ]] || fail "Jellyfin health: $health"
log "Jellyfin: $health"

# Phase 3: backup-arr-config.ps1 writes status.txt once it has run.
# shellcheck disable=SC2029
status="$(ssh "${ssh_opts[@]}" "$HOST" \
  "if (Test-Path '$REMOTE_DIR/status.txt') { Get-Content '$REMOTE_DIR/status.txt' }" | tr -d '\r')" ||
  fail "ssh to $HOST failed"
[[ -n "$status" ]] || exit 0

pull_latest arr-config
while IFS= read -r line; do log "$line"; done <<<"$status"
grep -q '^VPN: up' <<<"$status" || fail "VPN is not up on $HOST"
grep -q '^Backups: ok' <<<"$status" || fail "Phase 3 backups have a problem on $HOST"

# Sonarr, Radarr and Prowlarr answer /ping without a login. qBittorrent and Bazarr
# only need to answer at all (their login page).
for app in Sonarr:8989/ping Radarr:7878/ping Prowlarr:9696/ping qBittorrent:8080/ Bazarr:6767/; do
  name="${app%%:*}"
  curl -sS -o /dev/null --max-time 10 "http://$server:${app#*:}" || fail "$name on $server did not answer"
done
log "Apps: all answered"
