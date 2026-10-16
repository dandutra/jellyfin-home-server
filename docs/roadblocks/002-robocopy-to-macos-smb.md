# 002: Robocopy to a macOS SMB share copied 0 files

**Phase:** 1 · **Date:** 2026-10-16 · **Time lost:** ~1h

## Problem
`scripts/windows/backup-user-files.ps1` copies each user's personal folders with robocopy to a shared folder on the Mac (macOS File Sharing over SMB). The script created its top folder and wrote one robocopy log per user folder, but no files reached the Mac. The Windows install is in Portuguese, so the logs were too.

First run, for every folder:

```
ERRO 2 (0x00000002) Criando Diretório de Destino \\<mac>\laptop-backup\...\<user>\Documents\
O sistema não pode encontrar o arquivo especificado.
```

(Error 2 creating the destination folder: "the system cannot find the file specified.")

Second run: the folders appeared on the Mac, but the summary showed every file in the FALHA (failed) column, with `ERRO 5` ("Acesso negado", access denied) on subfolders and `ERRO 1359` ("Erro interno", internal error) on files.

## What I tried
1. Checked the share itself. The script had already created a folder and written logs on it, so the connection and the write permission worked.
2. The first error came up only when robocopy had to create two folder levels at once (`<user>\Documents`). I made the script create each destination folder with `New-Item` before robocopy runs. Error 2 went away, and the folders appeared.
3. The second run still failed. On the Mac, `ls -lO` showed the `uchg` flag (user immutable) on every folder that robocopy had created.

## Root cause
Windows marks shell folders such as Documents, Pictures and Desktop with the Read-only attribute. It is only a marker there and does not block writes. Robocopy copies folder attributes by default (`/DCOPY:DA`). The macOS SMB server turns the Read-only attribute into the `uchg` flag, which locks the folder. Robocopy then could not write into the folders it had just created.

## Fix
Robocopy now copies data and timestamps only (`/COPY:DT /DCOPY:DT`) ([26bfc4e](https://github.com/dandutra/jellyfin-home-server/commit/26bfc4e)). The third run copied 3,161 files (12 GB) with 0 failures. A few folders still got the `uchg` flag after their files were in place, so the runbook clears the flags on the Mac with `chflags -R nouchg` before the backup gets deleted.

## What I learned
File attributes do not mean the same thing on every file system. When I copy files between operating systems, I copy the data and timestamps and leave the metadata behind unless I need it. I also read the summary table of a copy tool, not only its exit code.
