# 004: icacls couldn't find my own account over SSH

**Phase:** 2 · **Date:** 2026-10-19 · **Time lost:** ~15 min

## Problem
`setup-jellyfin-service.ps1` stopped halfway when run over SSH from the Mac:

```
WORKGROUP\<admin>: No mapping between account names and security IDs was done.
icacls.exe D:\data /inheritance:r /grant:r ... WORKGROUP\<admin>:(OI)(CI)F ... failed with exit code 1332
```

The account switch and the crash-restart settings before it had worked. `D:\data` still had its old permissions, and the service hadn't restarted, so Jellyfin was still running as Network Service.

## What I tried
1. Checked what the half-run had changed before running anything again. `sc qc` showed the new account. `icacls D:\data` showed the old, inherited permissions: icacls checks every name before it changes anything, so one bad name meant no change at all.
2. Printed the environment over SSH: `USERDOMAIN=WORKGROUP`, `COMPUTERNAME=HOMESERVER`. Local accounts live under the computer name, so `WORKGROUP\<admin>` doesn't exist.

## Root cause
The script built the admin account's name from `$env:USERDOMAIN\$env:USERNAME`. In an OpenSSH session on a computer that isn't in a domain, `USERDOMAIN` is the workgroup name, not the computer name.

## Fix
The script now names the account by its security ID, taken from the token of the process running it:

```powershell
$admin = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
```

The script is safe to run again, so I ran the whole thing again. It finished, and Jellyfin started as `NT SERVICE\JellyfinServer` in 7 seconds.

## What I learned
Environment variables describe the session, not the account, and an SSH session isn't the same as signing in at the keyboard. To name the current user in an ACL, I now use the SID, which has no domain part to get wrong. A script that is safe to run again also made this cheap to recover from: fix one line, run it again.
