<#
.SYNOPSIS
    Collects what we need to know about the laptop before wiping it.

.DESCRIPTION
    Read-only. Writes a battery report and a summary to the Desktop:
    model, BIOS version, storage controller mode (RAID/RST vs AHCI), disks,
    activation status, whether a product key is stored in firmware, and the
    size of each user's folders so we know how much the backup needs.

    The summary contains the service tag; don't commit it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\pre-wipe-checks.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Stop'
$summary = Join-Path $OutDir 'pre-wipe-summary.txt'
$batteryReport = Join-Path $OutDir 'battery-report.html'

function Get-FolderSizeGB([string]$Path) {
    $bytes = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    [math]::Round([double]$bytes / 1GB, 2)
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Pre-wipe summary  $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$lines.Add('')

$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$lines.Add("Model:          $($cs.Manufacturer) $($cs.Model)")
$lines.Add("Service tag:    $($bios.SerialNumber)   (private, don't commit)")
$lines.Add("BIOS version:   $($bios.SMBIOSBIOSVersion)")
$lines.Add("RAM (GB):       $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1))")
$lines.Add('')

# "Intel RST" / "RAID" here means the BIOS is in RAID On mode. Setup won't see
# the NVMe drive in that mode without extra drivers; we switch to AHCI.
$lines.Add('Storage controllers:')
Get-CimInstance Win32_SCSIController | ForEach-Object { $lines.Add("  - $($_.Name)") }
Get-CimInstance Win32_IDEController | ForEach-Object { $lines.Add("  - $($_.Name)") }
$lines.Add('Disks:')
Get-PhysicalDisk | ForEach-Object {
    $lines.Add("  - $($_.FriendlyName)  $([math]::Round($_.Size / 1GB))GB  $($_.BusType)  $($_.MediaType)")
}
$lines.Add('')

$license = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
    Where-Object { $_.Name -like 'Windows*' } | Select-Object -First 1
$statusNames = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOB grace'; 3 = 'OOT grace'; 4 = 'Non-genuine grace'; 5 = 'Notification'; 6 = 'Extended grace' }
$lines.Add("Windows edition: $((Get-CimInstance Win32_OperatingSystem).Caption)")
if ($license) {
    $lines.Add("License status:  $($statusNames[[int]$license.LicenseStatus])")
    $lines.Add("License channel: $($license.ProductKeyChannel)")
}
$sls = Get-CimInstance SoftwareLicensingService
if ($sls.OA3xOriginalProductKeyDescription) {
    $lines.Add("Firmware key:    present ($($sls.OA3xOriginalProductKeyDescription))")
} else {
    $lines.Add('Firmware key:    none (choose Windows 11 Pro manually during setup)')
}
$lines.Add('')

$lines.Add('User folders (GB), to size the backup:')
$skip = 'Public', 'Default', 'Default User', 'All Users'
Get-ChildItem C:\Users -Directory -Force | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
    $user = $_
    $lines.Add("  $($user.Name):")
    foreach ($folder in 'Desktop', 'Documents', 'Pictures', 'Videos', 'Music', 'Downloads', 'OneDrive') {
        $path = Join-Path $user.FullName $folder
        if (Test-Path -LiteralPath $path) {
            $lines.Add(("    {0,-10} {1,8}" -f $folder, (Get-FolderSizeGB $path)))
        }
    }
}

powercfg /batteryreport /output $batteryReport | Out-Null
$lines.Add('')
$lines.Add("Battery report: $batteryReport")

$lines | Set-Content -LiteralPath $summary -Encoding UTF8
$lines | Write-Output
Write-Output ''
Write-Output "Saved to $summary"
