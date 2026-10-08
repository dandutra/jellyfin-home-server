# Decisions

Short records of why the server is built the way it is. Format: Context → Decision → Consequences.

| # | Decision |
|---|---|
| [001](001-clean-install-over-reset.md) | Clean install from USB, not "Reset this PC" |
| [002](002-native-windows-no-docker.md) | Native Windows services, no Docker |
| [003](003-separate-media-drive.md) | Separate 500 GB SSD for media |
| [004](004-4k-direct-play-only.md) | 4K is direct play only |
| [005](005-ssh-lan-only-no-rdp.md) | SSH is key-only and LAN-only; no RDP |
| [006](006-service-accounts.md) | Each service runs under its own low-privilege account |
| [007](007-config-and-media-layout.md) | Configs on C:, all media in one tree on D: |
