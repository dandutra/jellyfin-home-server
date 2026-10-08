# 003: Separate 500 GB SSD for media

**Context:**
- The 256 GB NVMe leaves about 180 GB after Windows.
- The only external drive is the family photo backup and shouldn't be worn out by streaming and torrents.
- The Latitude 3410 has a free 2.5" SATA bay.
- At purchase time (Oct 2026) the cheapest 1 TB SSD was $179 CAD, and 1 TB 2.5" HDDs cost about the same or more. Budget is ~$100 CAD.

**Decision:** Add a 500 GB 2.5" 7 mm SATA SSD as `D:`, used for media only. The OS, apps and their configs stay on `C:`.

**Why 500 GB is enough:**
- Media is watched and then deleted, not archived.
- Downloads and the library sit on the same volume, so Phase 3 uses hardlinks: each file takes its space once, even while seeding.
- Most content is 1080p (2–10 GB per movie). Only one TV can play 4K.

**Consequences:**
- Roughly 50–80 1080p movies fit at once.
- If the drive is lost or replaced, only media is gone. The setup survives.
- Bays shipped empty need Dell cable 07CR4F + bracket (an AliExpress order, 10–12 days delivery).
