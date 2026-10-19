<#
.SYNOPSIS
    Zips Jellyfin's configuration for the Mac to pull. Optionally schedules itself nightly.

.DESCRIPTION
    Stops Jellyfin for the copy, because its databases can't be copied
    safely while it writes to them, then starts it again (usually under a
    minute). Leaves out cache, transcodes, trickplay and log folders, which
    Jellyfin rebuilds.

    The zip contains API keys and password hashes, so the output folder is
    readable by Administrators and SYSTEM only. Keeps the newest 2 zips
    here; the Mac keeps 7.

    -Register copies this script to C:\ProgramData\homeserver\scripts
    (Administrators and SYSTEM only, so no other account can change what
    the SYSTEM task runs) and schedules it daily at 03:30, before the
    04:00 update window.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\backup-jellyfin-config.ps1 -Register
#>
[CmdletBinding()]
param(
    [string]$JellyfinDataDir = (Join-Path $env:ProgramData 'Jellyfin\Server'),
    [string]$OutDir = (Join-Path $env:ProgramData 'homeserver\backup'),
    [switch]$Register
)

$ErrorActionPreference = 'Stop'
$serviceName = 'JellyfinServer'
$homeDir = Join-Path $env:ProgramData 'homeserver'

function Protect-AdminOnly([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $Path" }
}

if ($Register) {
    $scriptDir = Join-Path $homeDir 'scripts'
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Protect-AdminOnly $homeDir
    $target = Join-Path $scriptDir 'backup-jellyfin-config.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:30'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName 'homeserver-config-backup' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Output "Scheduled daily at 03:30: $target"
    return
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Protect-AdminOnly $homeDir
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$staging = Join-Path $env:TEMP "jellyfin-config-$stamp"
$zip = Join-Path $OutDir "jellyfin-config-$stamp.zip"

$wasRunning = (Get-Service $serviceName).Status -eq 'Running'
try {
    if ($wasRunning) { Stop-Service $serviceName }
    # robocopy exit codes below 8 mean success.
    & robocopy.exe $JellyfinDataDir $staging /E /R:1 /W:1 /NP /NFL /NDL /XD cache transcodes trickplay log | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
} finally {
    if ($wasRunning) { Start-Service $serviceName }
}

try {
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -Force
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}

Get-ChildItem -Path $OutDir -Filter 'jellyfin-config-*.zip' |
    Sort-Object Name -Descending | Select-Object -Skip 2 |
    Remove-Item -Force

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Output "Wrote $zip ($size MB)"
