# 004: 4K is direct play only

**Context:**
- **Clients:** LG 43UT7000 (webOS, 4K HDR), a Fire TV Stick (1080p) plugged into a TCL Roku TV, and the Roku app itself, which the Fire Stick replaces.
- **GPU:** the UHD 620's Quick Sync decodes and encodes HEVC 10-bit. But converting 4K HDR to SDR on the fly is heavy: about one stream at best on this iGPU.
- **Load:** at most two streams at the same time.

**Decision:**
- 4K files are only for the LG, which plays them directly with no transcoding.
- Other clients get 1080p, transcoded by Quick Sync when needed.
- No attempt at 4K HDR → SDR conversion for every client.

**Consequences:**
- Two 1080p transcodes, or one 4K direct play plus one 1080p transcode, fit comfortably.
- 4K downloads are a deliberate choice for the LG, which also helps the 500 GB budget ([003](003-separate-media-drive.md)).
