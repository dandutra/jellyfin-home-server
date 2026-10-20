# Roadblocks

One file per problem that took real effort to get past, named `NNN-short-title.md`. Each file follows the template below so it can be turned straight into an interview answer.

| # | Roadblock | Phase |
|---|---|---|
| 001 | [ClamAV reported "clean" after scanning 0 files](001-clamscan-scanned-nothing.md) | 1 |
| 002 | [Robocopy to a macOS SMB share copied 0 files](002-robocopy-to-macos-smb.md) | 1 |
| 003 | [Windows put its boot files on the USB stick](003-boot-files-on-the-usb-stick.md) | 1 |
| 004 | [icacls couldn't find my own account over SSH](004-icacls-workgroup-over-ssh.md) | 2 |
| 005 | [The Fire TV looped on Big Buck Bunny without ever starting it](005-fire-tv-retry-loop-on-old-mov.md) | 2 |
| 006 | [After moving the server, nothing could reach it](006-public-network-after-the-move.md) | 3 |

## Template

```markdown
# NNN: <title>

**Phase:** 1 / 2 / 3 · **Date:** YYYY-MM-DD · **Time lost:** ~Xh

## Problem
What I was trying to do and what actually happened (exact error text).

## What I tried
1. ...and why it didn't work.

## Root cause
The actual reason, in one or two sentences.

## Fix
What worked. Link the commit/script.

## What I learned
The takeaway I'd carry to the next project.
```
