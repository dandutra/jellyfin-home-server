<#
.SYNOPSIS
    Runs the Jellyfin service under its own virtual account, with read-only media access.

.DESCRIPTION
    See docs/decisions/006-service-accounts.md and 007-config-and-media-layout.md.

    Run it after installing Jellyfin, and again after every Jellyfin upgrade:
    the installer removes and re-creates the JellyfinServer service, which
    puts the account back to Network Service. Safe to run again.

    - Creates the media tree on D: (movies, tv, torrents\incomplete,
      torrents\completed).
    - Switches the service to NT SERVICE\JellyfinServer and sets it to
      restart after a crash.
    - Locks D:\data down to Administrators, SYSTEM and the admin account
      running this script (full control), plus NT SERVICE\JellyfinServer
      (read only). A new NTFS volume lets every signed-in user, and every
      service, change files at its root; this takes that away under D:\data.
    - Gives NT SERVICE\JellyfinServer modify rights on its data folder,
      since files there may belong to Network Service from the first run.
    - Restarts the service.
    - Opens TCP 8096 (web and apps) and UDP 7359 (app auto-discovery) to
      the local subnet on the Private profile.

    Doesn't touch Jellyfin's settings, libraries or users.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-jellyfin-service.ps1
#>
[CmdletBinding()]
param(
    [string]$DataRoot = 'D:\data',
    [string]$JellyfinDataDir = (Join-Path $env:ProgramData 'Jellyfin\Server')
)

$ErrorActionPreference = 'Stop'
$serviceName = 'JellyfinServer'
$account = "NT SERVICE\$serviceName"
$admin = "$env:USERDOMAIN\$env:USERNAME"

function Invoke-Checked {
    $exe, $rest = $args
    & $exe @rest | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$exe $($rest -join ' ') failed with exit code $LASTEXITCODE" }
}

if (-not (Get-Service $serviceName -ErrorAction SilentlyContinue)) {
    throw "No $serviceName service. Install Jellyfin with 'Install as a Service' first."
}
if (-not (Test-Path $JellyfinDataDir)) { throw "Jellyfin data folder not found: $JellyfinDataDir" }

# 1. Media tree.
$media = Join-Path $DataRoot 'media'
foreach ($sub in 'movies', 'tv', 'torrents\incomplete', 'torrents\completed') {
    New-Item -ItemType Directory -Path (Join-Path $media $sub) -Force | Out-Null
}

# 2. Service account. A virtual account needs the service SID turned on, and has no password.
Invoke-Checked sc.exe sidtype $serviceName unrestricted
Invoke-Checked sc.exe config $serviceName obj= $account
# Restart 1 minute after a crash or a non-zero exit, three times a day at most.
Invoke-Checked sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000
Invoke-Checked sc.exe failureflag $serviceName 1

# 3. Permissions. Dropping inheritance on D:\data removes the rights it got from
# the root of D:. *S-1-5-32-544 = Administrators, *S-1-5-18 = SYSTEM.
Invoke-Checked icacls.exe $DataRoot /inheritance:r `
    /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' "${admin}:(OI)(CI)F" "${account}:(OI)(CI)RX"
Invoke-Checked icacls.exe $JellyfinDataDir /grant "${account}:(OI)(CI)M" /T /C /Q

Restart-Service $serviceName

# 4. Firewall.
$rules = @(
    @{ Name = 'Jellyfin-HTTP-In'; DisplayName = 'Jellyfin web and apps (LAN)'; Protocol = 'TCP'; LocalPort = 8096 },
    @{ Name = 'Jellyfin-Discovery-In'; DisplayName = 'Jellyfin auto-discovery (LAN)'; Protocol = 'UDP'; LocalPort = 7359 }
)
foreach ($r in $rules) {
    Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
    New-NetFirewallRule @r -Direction Inbound -Action Allow -Profile Private -RemoteAddress LocalSubnet | Out-Null
}

Start-Sleep -Seconds 5
$svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
Write-Output "Service: $($svc.State), runs as $($svc.StartName), start mode $($svc.StartMode)"
Write-Output "Permissions on ${DataRoot}:"
& icacls.exe $DataRoot
