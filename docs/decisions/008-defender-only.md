# 008: Microsoft Defender is the only antivirus on the server

**Context:**
- The old install ran Kaspersky (paid). Kaspersky put Defender in passive mode, and it did the pre-backup full scan.
- The server has 8 GB of RAM, shared by Jellyfin, transcoding and, in Phase 3, four more services.
- Two real-time scanners on one machine fight over the same files. The runbook already avoids that during the backup.
- The server runs a few known programs, and nobody browses the web on it.

**Decision:**
- **Defender only**, built into Windows 11 Pro and updated through Windows Update.
- No third-party antivirus on the server.

**Consequences:**
- Nothing to install or license, and one less background service using RAM.
- Real-time scanning of the media tree on `D:` can slow down reads during playback and imports. If that happens, Phase 2 adds a Defender exclusion for the media folders only, never for the config folders or the downloads folder.
- The family's Kaspersky licence is free for another device.
