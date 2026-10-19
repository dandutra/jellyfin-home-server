<#
.SYNOPSIS
    Keeps the server awake on AC and schedules Windows Update restarts for 04:00.

.DESCRIPTION
    Safe to run again. Changes only these settings:

    Power (AC only, battery settings untouched):
    - never sleep, never hibernate, never spin down disks
    - screen off after 5 minutes
    - closing the lid does nothing
    - hibernation off. That also turns off Fast Startup, which makes F2/F12
      at the Dell logo work again.

    Windows Update, through the same registry policies gpedit.msc writes
    (Computer Configuration > Administrative Templates > Windows Components
    > Windows Update):
    - download and install automatically, every day at 04:00, restarting
      if needed
    - active hours 05:00-23:00, so Windows never restarts during the day
      for an update

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\set-power-and-updates.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-PowerCfg {
    & powercfg.exe @args
    if ($LASTEXITCODE -ne 0) { throw "powercfg $($args -join ' ') failed" }
}

Invoke-PowerCfg /change standby-timeout-ac 0
Invoke-PowerCfg /change hibernate-timeout-ac 0
Invoke-PowerCfg /change disk-timeout-ac 0
Invoke-PowerCfg /change monitor-timeout-ac 5
Invoke-PowerCfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
Invoke-PowerCfg /setactive SCHEME_CURRENT
Invoke-PowerCfg /hibernate off

function Write-Policy([string]$Path, [string]$Name, [int]$Value) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = "$wu\AU"
Write-Policy $au NoAutoUpdate 0
Write-Policy $au AUOptions 4               # auto download and schedule the install
Write-Policy $au ScheduledInstallDay 0     # every day
Write-Policy $au ScheduledInstallTime 4    # 04:00
Write-Policy $au ScheduledInstallEveryWeek 1
Write-Policy $wu SetActiveHours 1
Write-Policy $wu ActiveHoursStart 5
Write-Policy $wu ActiveHoursEnd 23

Write-Output 'Power (AC):'
& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'Current AC'
# LIDACTION is a hidden setting: /query prints nothing for it, /qh does
& powercfg.exe /qh SCHEME_CURRENT SUB_BUTTONS LIDACTION | Select-String 'Current AC'
Write-Output ''
Write-Output 'Windows Update policy:'
Get-ItemProperty $au | Select-Object NoAutoUpdate, AUOptions, ScheduledInstallDay, ScheduledInstallTime | Format-List
Get-ItemProperty $wu | Select-Object SetActiveHours, ActiveHoursStart, ActiveHoursEnd | Format-List
