<#
.SYNOPSIS
    Zips the Phase 3 apps' configuration for the Mac to pull, and writes the
    VPN status. Optionally schedules itself nightly.

.DESCRIPTION
    - Sonarr, Radarr, Prowlarr and Bazarr: copies the newest zip from each
      app's own scheduled backup (set to daily in the apps). Those are made
      with SQLite's online backup, so the apps keep running. A zip older
      than 2 days is reported as stale.
    - qBittorrent: stops it for the copy (a few seconds), because its
      resume files change while it runs. Logs are left out.
    - Writes status.txt next to the zips: one "VPN:" line and one
      "Backups:" line, which the Mac logs. VPN up means the tunnel service
      runs, the last handshake is under 5 minutes old, and Nord's own
      check says the traffic comes through the VPN. No IP address is
      written.

    The zip holds API keys and password hashes, so the output folder is
    readable by Administrators and SYSTEM only. Keeps the newest 2 zips
    here; the Mac keeps 7.

    -Register copies this script to C:\ProgramData\homeserver\scripts
    (Administrators and SYSTEM only) and schedules it daily at 03:35,
    after the Jellyfin backup and before the Mac pulls at 03:50.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\backup-arr-config.ps1 -Register
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:ProgramData 'homeserver\backup'),
    [string]$TunnelName = 'nord-wg',
    [switch]$Register
)

$ErrorActionPreference = 'Stop'
$homeDir = Join-Path $env:ProgramData 'homeserver'
$qbtProfile = Join-Path $env:ProgramData 'qBittorrent'
# Where each app keeps its scheduled backups.
$appBackups = [ordered]@{
    Sonarr   = Join-Path $env:ProgramData 'Sonarr\Backups\scheduled'
    Radarr   = Join-Path $env:ProgramData 'Radarr\Backups\scheduled'
    Prowlarr = Join-Path $env:ProgramData 'Prowlarr\Backups\scheduled'
    Bazarr   = Join-Path $env:ProgramData 'Bazarr\backup'
}

function Protect-AdminOnly([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $Path" }
}

function Get-VpnStatus([string]$Tunnel) {
    $svc = Get-Service "WireGuardTunnel`$$Tunnel" -ErrorAction SilentlyContinue
    if (-not $svc) { return 'DOWN (no tunnel service)' }
    if ($svc.Status -ne 'Running') { return "DOWN (tunnel service $($svc.Status))" }

    $wg = Join-Path $env:ProgramFiles 'WireGuard\wg.exe'
    $line = & $wg show $Tunnel latest-handshakes 2>$null | Select-Object -First 1
    if ($line -notmatch '\s(\d+)$' -or [long]$Matches[1] -eq 0) { return 'DOWN (no handshake)' }
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$Matches[1]
    # WireGuard re-handshakes every 2 minutes while traffic flows.
    if ($age -gt 300) { return "DOWN (last handshake $age s ago)" }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $insights = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 'https://api.nordvpn.com/v1/helpers/ips/insights'
    } catch {
        return 'up (Nord IP check failed)'
    }
    if ($insights.protected) { return 'up' }
    return 'DOWN (Nord says traffic is not protected)'
}

if ($Register) {
    $scriptDir = Join-Path $homeDir 'scripts'
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Protect-AdminOnly $homeDir
    $target = Join-Path $scriptDir 'backup-arr-config.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:35'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    Register-ScheduledTask -TaskName 'homeserver-arr-backup' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Output "Scheduled daily at 03:35: $target"
    return
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Protect-AdminOnly $homeDir
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$staging = Join-Path $env:TEMP "arr-config-$stamp"
$zip = Join-Path $OutDir "arr-config-$stamp.zip"
$problems = @()

try {
    # 1. The apps' own backups.
    foreach ($app in $appBackups.Keys) {
        if (-not (Get-Service | Where-Object Name -like "*$app*")) { continue }
        $newest = Get-ChildItem -Path $appBackups[$app] -Filter '*.zip' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $newest) { $problems += "$app has no backup"; continue }
        if ($newest.LastWriteTime -lt (Get-Date).AddDays(-2)) { $problems += "$app backup is stale" }
        $dest = Join-Path $staging $app
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -LiteralPath $newest.FullName -Destination $dest
    }

    # 2. qBittorrent, stopped for the copy.
    if (Get-Service qBittorrent -ErrorAction SilentlyContinue) {
        $wasRunning = (Get-Service qBittorrent).Status -eq 'Running'
        try {
            if ($wasRunning) { Stop-Service qBittorrent }
            # robocopy exit codes below 8 mean success.
            & robocopy.exe $qbtProfile (Join-Path $staging 'qBittorrent') /E /R:1 /W:1 /NP /NFL /NDL /XD logs | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
        } finally {
            if ($wasRunning) { Start-Service qBittorrent }
        }
    }

    if (Test-Path $staging) {
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -Force
    } else {
        $problems += 'nothing to back up'
    }
} finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}

Get-ChildItem -Path $OutDir -Filter 'arr-config-*.zip' |
    Sort-Object Name -Descending | Select-Object -Skip 2 |
    Remove-Item -Force

# 3. Status for the Mac.
$backups = if ($problems) { 'PROBLEM (' + ($problems -join '; ') + ')' } else { 'ok' }
$status = @("VPN: $(Get-VpnStatus $TunnelName)", "Backups: $backups")
Set-Content -Path (Join-Path $OutDir 'status.txt') -Value $status -Encoding ASCII
$status
if (Test-Path $zip) { Write-Output "Wrote $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)" }
