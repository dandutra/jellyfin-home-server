<#
.SYNOPSIS
    Copies personal files from every user profile to the backup drive.

.DESCRIPTION
    Only personal data is copied. Executables, scripts, installers, shortcuts
    and macro-enabled Office files are skipped on purpose: they're the files
    most likely to carry an infection back onto the clean install, and
    anything we need of that kind can be downloaded again.

    Everything lands in <Destination>\laptop-backup-<yyyy-MM>\<user>\<folder>.
    A robocopy log per folder goes next to it.

    Run it from an elevated PowerShell so it can read every profile. A network
    share mapped in a normal (non-elevated) window is invisible to an elevated
    one, so pass the share's UNC path instead of a mapped drive letter.

.PARAMETER Destination
    Where to write the backup: a drive root (E:\) or a network share
    (\\192.0.2.10\laptop-backup).

.PARAMETER IncludeOneDrive
    Also copy each user's OneDrive folder. Online-only files get downloaded
    first, which can take a while. Files already in OneDrive are safe in the
    cloud anyway, so this is off by default.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\backup-user-files.ps1 -Destination \\192.0.2.10\laptop-backup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [switch]$IncludeOneDrive
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Destination)) { throw "Destination not reachable: $Destination" }
$root = Join-Path $Destination "laptop-backup-$(Get-Date -Format 'yyyy-MM')"
New-Item -ItemType Directory -Path $root -Force | Out-Null

$folders = 'Desktop', 'Documents', 'Pictures', 'Videos', 'Music', 'Downloads'
if ($IncludeOneDrive) { $folders += 'OneDrive' }

$excludeFiles = '*.exe', '*.msi', '*.dll', '*.scr', '*.com', '*.bat', '*.cmd', '*.ps1',
    '*.vbs', '*.vbe', '*.js', '*.jse', '*.wsf', '*.hta', '*.lnk', '*.url', '*.pif',
    '*.docm', '*.xlsm', '*.pptm', '*.dotm', 'desktop.ini', 'Thumbs.db'

# Real user profiles only. Listing C:\Users also returns localized junctions
# (e.g. the Portuguese "All Users") and template profiles that a name filter misses.
$users = Get-CimInstance Win32_UserProfile -Filter 'Special = False' |
    Where-Object { Test-Path -LiteralPath $_.LocalPath } |
    ForEach-Object { Get-Item -LiteralPath $_.LocalPath }

$failed = $false
foreach ($user in $users) {
    foreach ($folder in $folders) {
        $src = Join-Path $user.FullName $folder
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $root "$($user.Name)\$folder"
        $log = Join-Path $root "robocopy-$($user.Name)-$folder.log"
        Write-Output "Copying $src -> $dst"
        # /E all subfolders, /XJ skip junctions (avoids loops), /R:1 /W:1 don't hang on locked files
        robocopy $src $dst /E /XJ /R:1 /W:1 /NP /XF $excludeFiles /LOG:$log | Out-Null
        # robocopy exit codes 0-7 are success variants; 8+ means something failed
        if ($LASTEXITCODE -ge 8) {
            Write-Warning "Errors copying $src (exit $LASTEXITCODE), see $log"
            $failed = $true
        }
    }
}

Write-Output ''
Write-Output "Backup written to $root"
Write-Output 'Also export browser bookmarks/passwords by hand (or confirm browser sync is on).'
if ($failed) { exit 1 }
