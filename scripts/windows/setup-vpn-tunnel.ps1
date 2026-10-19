<#
.SYNOPSIS
    Runs a NordVPN WireGuard config as a WireGuard tunnel service that connects at boot.

.DESCRIPTION
    See docs/decisions/010-vpn-kill-switch-native.md.

    Run it after installing WireGuard for Windows, and again with a new
    config file whenever the Nord server in the old one stops working.
    Safe to run again.

    - Refuses to run while the NordVPN app is installed: its NordLynx
      adapter and its own routes would fight the tunnel's.
    - Changes AllowedIPs 0.0.0.0/0 to 0.0.0.0/1, 128.0.0.0/1 (and ::/0 to
      ::/1, 8000::/1). All internet traffic still goes through the tunnel,
      but WireGuard's own kill switch stays off, so the LAN, SSH and
      Jellyfin keep working. qBittorrent's kill switch comes from
      setup-arr-services.ps1.
    - Saves the config to C:\ProgramData\homeserver\vpn (Administrators and
      SYSTEM only). The file holds the tunnel's private key.
    - Installs it as the service WireGuardTunnel$<TunnelName>, replacing an
      older one of the same name.
    - Reports the service state, the last handshake and whether Nord sees
      the server's traffic as coming through the VPN. Prints no IP address.

    Doesn't touch the firewall or any other app.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-vpn-tunnel.ps1 -ConfigPath $HOME\Downloads\nord.conf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,
    [string]$TunnelName = 'nord-wg'
)

$ErrorActionPreference = 'Stop'
$wireguard = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
$wg = Join-Path $env:ProgramFiles 'WireGuard\wg.exe'
$vpnDir = Join-Path $env:ProgramData 'homeserver\vpn'
$serviceName = "WireGuardTunnel`$$TunnelName"

if (-not (Test-Path $wireguard)) { throw "WireGuard for Windows not found at $wireguard. Install it first." }
if (Get-Service nordvpn-service -ErrorAction SilentlyContinue) {
    throw 'The NordVPN app is installed. Uninstall it first (runbook step 1).'
}
if ($TunnelName -notmatch '^[a-zA-Z0-9_=+.-]{1,32}$') { throw "Not a valid WireGuard tunnel name: $TunnelName" }

# 1. Rewrite the routes. Nord's file has one [Peer] with AllowedIPs = 0.0.0.0/0.
$text = [IO.File]::ReadAllText((Resolve-Path $ConfigPath))
if ($text -notmatch '(?m)^\s*PrivateKey\s*=') { throw "$ConfigPath has no PrivateKey. Is it a WireGuard config?" }
if ($text -notmatch '(?m)^\s*AllowedIPs\s*=.*(0\.0\.0\.0/0|0\.0\.0\.0/1)') {
    throw "$ConfigPath doesn't route all IPv4 traffic (no 0.0.0.0/0 in AllowedIPs)."
}
$text = [regex]::Replace($text, '(?m)^(\s*AllowedIPs\s*=.*)$', {
        param($m)
        $m.Value.Replace('0.0.0.0/0', '0.0.0.0/1, 128.0.0.0/1').Replace('::/0', '::/1, 8000::/1')
    })

# 2. Save it where only Administrators and SYSTEM can read it.
New-Item -ItemType Directory -Path $vpnDir -Force | Out-Null
& icacls.exe $vpnDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed on $vpnDir" }
$target = Join-Path $vpnDir "$TunnelName.conf"
[IO.File]::WriteAllText($target, $text, (New-Object Text.UTF8Encoding $false))

# 3. (Re)install the tunnel service. wireguard.exe is a GUI program, so wait for it explicitly.
function Invoke-WireGuard([string[]]$Arguments) {
    $p = Start-Process -FilePath $wireguard -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "wireguard.exe $($Arguments -join ' ') failed with exit code $($p.ExitCode)" }
}
if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    Invoke-WireGuard '/uninstalltunnelservice', $TunnelName
    for ($i = 0; $i -lt 30 -and (Get-Service $serviceName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
}
Invoke-WireGuard '/installtunnelservice', "`"$target`""

# 4. Report. A handshake means the Nord server answered.
$age = $null
for ($i = 0; $i -lt 30 -and $null -eq $age; $i++) {
    Start-Sleep -Seconds 1
    $line = & $wg show $TunnelName latest-handshakes 2>$null | Select-Object -First 1
    if ($line -match '\s(\d+)$' -and [long]$Matches[1] -gt 0) {
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$Matches[1]
    }
}
$svc = Get-CimInstance Win32_Service | Where-Object Name -eq $serviceName
Write-Output "Service: $($svc.Name) $($svc.State), start mode $($svc.StartMode)"
if ($null -eq $age) { Write-Output 'Handshake: none after 30 s' } else { Write-Output "Handshake: $age s ago" }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $insights = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 'https://api.nordvpn.com/v1/helpers/ips/insights'
    Write-Output "Nord says protected: $($insights.protected)"
} catch {
    Write-Output "Nord IP check failed: $($_.Exception.Message)"
}
Write-Output "Saved to $target. Delete the downloaded copy: $ConfigPath"
