<#
.SYNOPSIS
    Runs qBittorrent, Sonarr, Radarr, Prowlarr and Bazarr under their own virtual
    accounts, with LAN-only web pages and qBittorrent's firewall kill switch.

.DESCRIPTION
    See docs/decisions/006-service-accounts.md, 010-vpn-kill-switch-native.md
    and 011-qbittorrent-under-nssm.md.

    Run it after installing the apps, and again after any of their installers
    runs again: Sonarr, Radarr, Prowlarr and Bazarr reinstalls re-create the
    service on LocalService or Local System. Their built-in updaters keep the
    account. Apps that aren't installed yet are skipped, so it can run after
    each install. Safe to run again.

    - Copies NSSM from Jellyfin's folder to C:\ProgramData\homeserver\bin
      and creates the qBittorrent service with it (qBittorrent has no
      service mode). Needs qBittorrent's settings to exist in the profile
      folder first (runbook step 3).
    - Switches each service to NT SERVICE\<service> and sets it to restart
      after a crash.
    - Gives each account modify rights on its config folder, and takes away
      everyone else's except SYSTEM and Administrators. Gives
      qBittorrent, Sonarr, Radarr and Bazarr modify rights on D:\data\media.
      Prowlarr gets nothing on D:. Jellyfin's read-only access is unchanged.
    - Opens each web page's port to the local subnet on the Private profile.
    - Blocks qbittorrent.exe outbound on the physical adapters, and turns
      off inbound rules for qbittorrent.exe that Windows created when
      qBittorrent first ran at the desktop.
    - Restarts the services and prints their accounts, and the interface
      qBittorrent is bound to.

    Doesn't change any app's own settings.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-arr-services.ps1
#>
[CmdletBinding()]
param(
    [string]$MediaRoot = 'D:\data\media',
    [string]$VpnInterface = 'nord-wg',
    [string]$QbittorrentExe = (Join-Path $env:ProgramFiles 'qBittorrent\qbittorrent.exe'),
    [string]$QbittorrentProfile = (Join-Path $env:ProgramData 'qBittorrent'),
    [string]$NssmSource = (Join-Path $env:ProgramFiles 'Jellyfin\Server\nssm.exe')
)

$ErrorActionPreference = 'Stop'
$binDir = Join-Path $env:ProgramData 'homeserver\bin'
$nssm = Join-Path $binDir 'nssm.exe'

function Invoke-Checked {
    $exe, $rest = $args
    & $exe @rest | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$exe $($rest -join ' ') failed with exit code $LASTEXITCODE" }
}

# Service name, config folder, web port, and whether it writes to the media tree.
# Bazarr's installer picks its own service name, so look it up.
$bazarr = Get-Service | Where-Object Name -like '*bazarr*' | Select-Object -First 1 -ExpandProperty Name
$apps = @(
    @{ Service = 'qBittorrent'; Config = $QbittorrentProfile; Port = 8080; Media = $true },
    @{ Service = 'Sonarr'; Config = (Join-Path $env:ProgramData 'Sonarr'); Port = 8989; Media = $true },
    @{ Service = 'Radarr'; Config = (Join-Path $env:ProgramData 'Radarr'); Port = 7878; Media = $true },
    @{ Service = 'Prowlarr'; Config = (Join-Path $env:ProgramData 'Prowlarr'); Port = 9696; Media = $false },
    @{ Service = $bazarr; Config = (Join-Path $env:ProgramData 'Bazarr'); Port = 6767; Media = $true }
)

if (-not (Test-Path $MediaRoot)) { throw "Media folder not found: $MediaRoot. Run setup-jellyfin-service.ps1 first." }

# 1. qBittorrent service through NSSM. The settings must already exist: the GUI
# build run as a service has no desktop, so a first-run dialog would hang it.
if (Test-Path $QbittorrentExe) {
    $ini = Get-ChildItem $QbittorrentProfile -Recurse -Filter 'qBittorrent.ini' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $ini) { throw "No qBittorrent.ini under $QbittorrentProfile. Do runbook step 3 at the laptop first." }

    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    if (-not (Test-Path $nssm)) {
        if (-not (Test-Path $NssmSource)) { throw "NSSM not found at $NssmSource" }
        Copy-Item -LiteralPath $NssmSource -Destination $nssm
    }
    if (-not (Get-Service qBittorrent -ErrorAction SilentlyContinue)) {
        Invoke-Checked $nssm install qBittorrent $QbittorrentExe
    }
    # NSSM runs as the service's own account, so that account has to be able to start it.
    # The account name only resolves once the service exists.
    Invoke-Checked icacls.exe $binDir /grant 'NT SERVICE\qBittorrent:(OI)(CI)RX'
    Invoke-Checked $nssm set qBittorrent Application $QbittorrentExe
    Invoke-Checked $nssm set qBittorrent AppParameters "--profile=$QbittorrentProfile"
    Invoke-Checked $nssm set qBittorrent AppDirectory (Split-Path $QbittorrentExe)
    Invoke-Checked $nssm set qBittorrent DisplayName 'qBittorrent'
    Invoke-Checked $nssm set qBittorrent Description 'qBittorrent, run by NSSM. See setup-arr-services.ps1.'
    Invoke-Checked $nssm set qBittorrent Start SERVICE_AUTO_START
    # qBittorrent saves resume data when its window closes; give it 20 s before NSSM kills it.
    Invoke-Checked $nssm set qBittorrent AppStopMethodWindow 20000
    Invoke-Checked $nssm set qBittorrent AppExit Default Restart
    Invoke-Checked $nssm set qBittorrent AppRestartDelay 60000
} else {
    Write-Output "qBittorrent not installed ($QbittorrentExe), skipped."
}

# 2. Accounts and config folders.
$present = @()
foreach ($a in $apps) {
    if (-not $a.Service -or -not (Get-Service $a.Service -ErrorAction SilentlyContinue)) {
        if ($a.Service -ne 'qBittorrent') { Write-Output "$($a.Config | Split-Path -Leaf) not installed, skipped." }
        continue
    }
    $account = "NT SERVICE\$($a.Service)"
    Invoke-Checked sc.exe sidtype $a.Service unrestricted
    Invoke-Checked sc.exe config $a.Service obj= $account
    Invoke-Checked sc.exe failure $a.Service reset= 86400 actions= restart/60000/restart/60000/restart/60000
    Invoke-Checked sc.exe failureflag $a.Service 1
    if (-not (Test-Path $a.Config)) { throw "Config folder not found: $($a.Config)" }
    # The built-in updaters write to the program files under this folder too.
    Invoke-Checked icacls.exe $a.Config /grant "${account}:(OI)(CI)M" /T /C /Q
    # The *arr installers give Users Modify here, bin included, and ProgramData lets
    # Users add files to subfolders. Either way a standard account could change what
    # the service runs. Keep only SYSTEM, Administrators and the app (by SID, roadblock 004).
    Invoke-Checked icacls.exe $a.Config /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "${account}:(OI)(CI)M"
    Invoke-Checked icacls.exe $a.Config /remove:g '*S-1-5-32-545' '*S-1-3-0'
    if ($a.Media) { Invoke-Checked icacls.exe $MediaRoot /grant "${account}:(OI)(CI)M" }
    $present += $a
}

# 3. Firewall: web pages LAN-only.
foreach ($a in $present) {
    $name = "homeserver-$($a.Service)-WebUI-In"
    Remove-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name $name -DisplayName "$($a.Service) web page (LAN)" -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $a.Port -Profile Private -RemoteAddress LocalSubnet | Out-Null
}

# 4. qBittorrent kill switch: nothing from qbittorrent.exe leaves through a physical
# adapter. Replies to the LAN web page are part of an inbound connection and still pass.
if (Test-Path $QbittorrentExe) {
    $physical = @(Get-NetAdapter -Physical | Select-Object -ExpandProperty Name)
    Remove-NetFirewallRule -Name 'homeserver-qBittorrent-KillSwitch-Out' -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name 'homeserver-qBittorrent-KillSwitch-Out' `
        -DisplayName 'qBittorrent: block outside the VPN' -Direction Outbound -Action Block `
        -Program $QbittorrentExe -InterfaceAlias $physical -Profile Any | Out-Null

    # Windows asks "allow on private/public networks?" the first time qBittorrent
    # listens at the desktop, and adds inbound rules for the whole program.
    Get-NetFirewallApplicationFilter -Program $QbittorrentExe |
        Get-NetFirewallRule |
        Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' } |
        ForEach-Object {
            Disable-NetFirewallRule -Name $_.Name
            Write-Output "Disabled inbound rule: $($_.DisplayName)"
        }
}

# 5. Restart and report.
foreach ($a in $present) { Restart-Service $a.Service -Force }
Start-Sleep -Seconds 10
foreach ($a in $present) {
    $svc = Get-CimInstance Win32_Service | Where-Object Name -eq $a.Service
    Write-Output ('{0}: {1}, runs as {2}, start mode {3}' -f $svc.Name, $svc.State, $svc.StartName, $svc.StartMode)
}
if ($ini) {
    # qBittorrent 5 keeps the name in InterfaceName; Interface holds an ID like iftype53_32768.
    $bound = Select-String -Path $ini.FullName -Pattern '^Session\\InterfaceName=(.*)$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    if ($bound -eq $VpnInterface) {
        Write-Output "qBittorrent is bound to $VpnInterface."
    } else {
        Write-Warning "qBittorrent is bound to '$bound', not $VpnInterface. Fix it in Tools > Options > Advanced > Network interface."
    }
}
Write-Output "Permissions on ${MediaRoot}:"
& icacls.exe $MediaRoot
