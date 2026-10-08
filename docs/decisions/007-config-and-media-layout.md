# 007: Configs on C:, all media in one tree on D:

**Context:**
- Phase 3 downloads into `torrents\` and the library is in `movies\` and `tv\`.
- A hardlink only works within a single NTFS volume. If downloads and the library sit on different volumes, every file gets copied and stored twice.
- App configs are small databases that change often. Media is large and expendable.

**Decision:**
```
C:\ProgramData\<app>\     configs (each app's default location), backed up nightly to the Mac
D:\data\media\
├── movies\
├── tv\
└── torrents\
    ├── incomplete\
    └── completed\
```

**Consequences:**
- Hardlinks work, so seeding doesn't double the disk usage.
- Configs live on the faster NVMe and don't depend on the media drive being present.
- Losing `D:` loses only media. Restoring configs means unzipping last night's backup.
