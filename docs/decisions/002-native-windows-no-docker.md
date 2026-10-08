# 002: Native Windows services, no Docker

**Context:** Most Jellyfin and *arr guides assume Linux + Docker. On Windows, Docker means Docker Desktop on WSL2: a Linux VM taking RAM out of 8 GB, plus extra layers between Jellyfin and the Intel GPU for Quick Sync. The project goal is also to learn how Windows runs services: service accounts, permissions, firewall, Group Policy.

**Decision:** Every component (Jellyfin, and in Phase 3 qBittorrent, Sonarr, Radarr, Prowlarr) runs as a native Windows service, installed and configured by PowerShell scripts in this repo.

**Consequences:**
- More hand-written setup than a `docker-compose.yml`, but every step is visible and scripted.
- Quick Sync works without passing the GPU into a VM.
- Moving to containers later is still possible, because configs and media live in fixed, documented paths.
