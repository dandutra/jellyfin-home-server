<#
.SYNOPSIS
    Sets up the built-in OpenSSH Server for key-only admin logins from the LAN.

.DESCRIPTION
    See docs/decisions/005-ssh-lan-only-no-rdp.md. Safe to run again.

    - Installs the OpenSSH Server optional feature if it's missing.
    - Adds the given ed25519 public key to administrators_authorized_keys
      and restricts that file to Administrators and SYSTEM. sshd ignores
      the file if anyone else has access, and ignores ~\.ssh\authorized_keys
      for admin accounts.
    - Turns off password logins.
    - Limits the firewall rule to the local subnet on the Private profile.
    - Makes PowerShell the default shell and the service start automatically.

    Prints the server's host key fingerprint at the end. Compare it with
    what ssh shows on the Mac the first time you connect.

    Doesn't touch RDP, user accounts or any other firewall rule.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-ssh.ps1 -PublicKeyPath E:\homeserver_ed25519.pub
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublicKeyPath
)

$ErrorActionPreference = 'Stop'
$sshDir = Join-Path $env:ProgramData 'ssh'
$sshdConfig = Join-Path $sshDir 'sshd_config'
$adminKeys = Join-Path $sshDir 'administrators_authorized_keys'
$sshd = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
$ruleName = 'OpenSSH-Server-In-TCP'

$key = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
# Also catches a private key passed by mistake.
if ($key -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+( [^\r\n]*)?$') {
    throw "Not a single ed25519 public key: $PublicKeyPath"
}

# 1. Install the server if needed.
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Write-Output 'Installing OpenSSH Server (takes a few minutes)...'
    Get-WindowsCapability -Online -Name 'OpenSSH.Server*' |
        Where-Object State -ne 'Installed' |
        ForEach-Object { Add-WindowsCapability -Online -Name $_.Name | Out-Null }
}
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { throw 'sshd service still missing after install' }

# The first start creates sshd_config and the host keys.
if (-not (Test-Path $sshdConfig)) { Start-Service sshd; Start-Sleep -Seconds 2 }

# 2. Admin key file, Administrators and SYSTEM only (SIDs work in any UI language).
if (-not (Test-Path $adminKeys)) { New-Item -ItemType File -Path $adminKeys | Out-Null }
$existing = @(Get-Content -LiteralPath $adminKeys | ForEach-Object { $_.Trim() })
if ($existing -notcontains $key) {
    Add-Content -LiteralPath $adminKeys -Value $key -Encoding Ascii
    Write-Output 'Added the key to administrators_authorized_keys.'
} else {
    Write-Output 'Key already present.'
}
& icacls.exe $adminKeys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed on $adminKeys" }

# 3. Key-only logins. sshd uses the first value it reads for each option,
# so a block at the top of the file wins over anything below it, including
# the default "Match Group administrators" block at the end.
# Windows has no backend for keyboard-interactive, so it never prompts, but
# we turn it off anyway so the config says what it means.
$block = @(
    '# homeserver: key-only logins (ADR 005)',
    'PasswordAuthentication no',
    'KbdInteractiveAuthentication no',
    'PubkeyAuthentication yes'
)
$lines = @(Get-Content -LiteralPath $sshdConfig)
# Drop an older copy of the block, then put the current one on top.
$rest = @($lines | Where-Object { $block -notcontains $_ })
while ($rest.Count -gt 0 -and $rest[0] -eq '') { $rest = @($rest | Select-Object -Skip 1) }
$wanted = $block + '' + $rest
if (Compare-Object $lines $wanted -SyncWindow 0) {
    Copy-Item $sshdConfig "$sshdConfig.bak" -Force
    Set-Content -LiteralPath $sshdConfig -Value $wanted -Encoding Ascii
    Write-Output 'sshd_config: key-only block written (backup in sshd_config.bak).'
}
& $sshd -t
if ($LASTEXITCODE -ne 0) { throw 'sshd -t rejected sshd_config; restore sshd_config.bak' }

# 4. PowerShell as the login shell.
$regPath = 'HKLM:\SOFTWARE\OpenSSH'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
$shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-ItemProperty -Path $regPath -Name DefaultShell -Value $shell -PropertyType String -Force | Out-Null

# 5. Firewall: LAN only, Private profile only.
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound `
        -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
}
Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Private -RemoteAddress LocalSubnet

# 6. Start now and at every boot.
Set-Service sshd -StartupType Automatic
Restart-Service sshd

$notPrivate = @(Get-NetConnectionProfile | Where-Object NetworkCategory -ne 'Private')
if ($notPrivate.Count -gt 0) {
    Write-Warning "Not Private: $($notPrivate.InterfaceAlias -join ', '). The firewall rule only opens port 22 on Private networks."
}

Write-Output ''
Write-Output "sshd: $((Get-Service sshd).Status), startup $((Get-Service sshd).StartType)"
Write-Output 'Host key fingerprint (compare on the Mac at first connect):'
& (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe') -lf (Join-Path $sshDir 'ssh_host_ed25519_key.pub')
