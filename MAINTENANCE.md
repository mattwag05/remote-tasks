# Maintenance Log

## 2026-01-29: Pi Memory Optimization

**Issue:** Memory usage at 78% (6.2 GiB / 7.9 GiB), swap at 55%

**Root Cause:** Two stale Claude interactive sessions (PID 255662 = 3.7 GiB, PID 2040593 = 249 MiB) independent of the worker daemon

**Actions Taken:**

1. **Killed stale processes** — saved ~4 GiB
   ```bash
   kill -9 255662 2040593
   ```

2. **Added Docker memory limits** to `/home/matthewwagner/docker/compose/media-stack/docker-compose.yml`:
   - Jellyfin: 384m
   - Radarr/Sonarr/Prowlarr/Jellyseerr/FlareSolverr: 256m each
   - Gluetun/Bazarr: 192m each
   - qBittorrent: 128m
   - Recyclarr: 64m

3. **Disabled Whisparr and Lidarr** — saved ~265 MiB (commented out in compose file)

4. **Hardened claude-worker** at `/home/matthewwagner/.local/bin/claude-worker`:
   - Added 5-minute timeout on task execution (`timeout 300`)
   - Added stale process cleanup (kills `claude --print` processes older than 30 minutes)
   - Added memory logging for monitoring

**Results:**
- Memory usage: **78% → 26%** (6.2 GiB → 2.1 GiB)
- Swap usage: **55% → 5%** (1.1 GiB → 110 MiB)
- Available memory: 1.7 GiB → 5.7 GiB

**Future Prevention:**
- Worker now kills stale processes every 30s
- Memory usage logged every iteration for monitoring
- Docker containers capped to prevent unbounded growth
