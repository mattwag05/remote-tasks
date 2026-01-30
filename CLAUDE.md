# CLAUDE.md

Project-specific context for Claude Code when working with the Remote Tasks system.

## Project Overview

**Purpose:** Cross-machine async task delegation for Claude Code instances
**Status:** ✅ Active (deployed 2026-01-25)
**Machines:** MacBook Air, M1 MacBook Pro, Raspberry Pi 5 (Tailscale VPN)

**Replaced:** Old Redis-based claude-mesh with simpler Beads + SSH + ntfy approach

## Machine Inventory

| Machine | Alias | Tailscale IP | Has Worker | Status |
|---------|-------|--------------|------------|--------|
| MacBook Air | `air` | 100.79.26.89 | No | Primary (this machine) |
| M1 MacBook Pro | `mbp` | 100.77.15.109 | No | Available |
| Raspberry Pi 5 | `pi` | 100.121.76.86 | Yes | Active worker + ntfy |

## Tailscale Configuration

### Correct Startup Command

All homelab machines should use:
```bash
sudo tailscale up --accept-dns=false --advertise-tags=tag:homelab --ssh --accept-routes=false
```

**Note:** macOS GUI version is sandboxed and cannot run `--ssh`. Use regular SSH instead.

### Common Issues

- **Configuration drift:** Run `tailscale debug prefs` to verify settings match documented command
- **IP address changes:** Tailscale IPs can drift - always use MagicDNS hostnames in scripts (e.g., `raspberrypi` not `100.121.76.86`)
- **Requires all flags:** `tailscale up` requires mentioning all non-default flags or use `--reset`
- **MBP CLI path:** Tailscale installed via native installer creates `/usr/local/bin/tailscale` (may not be in PATH)

### Verifying Configuration

```bash
# Check current settings
tailscale debug prefs | jq '{RunSSH, CorpDNS, RouteAll, AdvertiseTags}'

# Check network status
tailscale status

# Verify connectivity
tailscale netcheck
```

## Quick Reference

### iPhone SSH Access (Termius)

**Setup:**
1. Termius host config: `100.79.26.89`, port 22, user `matthewwagner`, SSH key from Keychain
2. SSH in, run: `tmux new -s claude` (first time) or `tmux attach -t claude` (reconnect)
3. Start Claude: `claude`
4. Detach: `Ctrl+B` then `D` (session persists)

**Why tmux:** Allows disconnecting from SSH without killing Claude session

### Common Commands

```bash
# Direct execution (synchronous)
./scripts/pi-exec.sh "uptime"
./scripts/mbp-exec.sh "ls ~/Projects"

# Async delegation
./scripts/delegate.sh pi "Run tests in eigent project"
./scripts/delegate.sh mbp "Build and report errors"

# System status
./scripts/status.sh

# View task results
bd show <task-id>
bd list --assignee=pi --status=open
```

### Worker Management (Pi)

```bash
# Check status
ssh 100.121.76.86 "systemctl --user status claude-worker"

# View logs
ssh 100.121.76.86 "journalctl --user -u claude-worker -f"

# Restart
ssh 100.121.76.86 "systemctl --user restart claude-worker"
```

### ntfy Server (Pi)

```bash
# Check server
curl http://100.121.76.86:8091/claude-tasks

# Test notification
curl -d "Test message" http://100.121.76.86:8091/claude-tasks

# View Docker logs
ssh 100.121.76.86 "docker logs ntfy"
```

## Architecture

### Flow Diagram

```
Mac creates task → Beads (local JSONL) → Pi SSHes to Mac → reads Beads
                                    ↓
                             Executes with Claude
                                    ↓
                   SSHes to Mac → updates Beads → sends ntfy
```

**Critical detail:** Worker on Pi does NOT have its own Beads database. It SSHes to the Mac (`100.79.26.89`) and runs `bd` commands there via SSH. The Mac is the single source of truth for all Beads data.

### Component Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| Scripts | `scripts/` | SSH wrappers and task delegation |
| Worker | `worker/` | Reference copy (live: `~/.local/bin/claude-worker` on Pi) |
| ntfy | `ntfy/` | Reference copy (live: `~/Projects/ntfy/` on Pi) |
| Config | `config/machines.json` | Machine registry |
| Skill | `~/.claude/skills/remote/` | Claude Code skill integration |

## Worker Behavior

### Model Selection

The worker analyzes task complexity and chooses the appropriate model (3-tier):

| Complexity | Model | Triggers |
|------------|-------|----------|
| Complex | **opus** | Keywords: `security`, `architecture`, `algorithm`, `design pattern`, `audit`, `critical`, `sensitive` |
| Moderate | **sonnet** | Keywords: `refactor`, `test`, `debug`, `document`, `migrate`, `complex`, `design`, `implement.*feature`, `optimize` OR word count > 20 |
| Simple | **haiku** | All other tasks |

### Execution Flags

Worker always uses:
```bash
claude --print --model <haiku|sonnet|opus> --dangerously-skip-permissions "<task>"
```

- `--print`: Headless execution (no interactive mode)
- `--model`: Auto-selected based on complexity (haiku/sonnet/opus)
- `--dangerously-skip-permissions`: No user prompts (full autonomy)

### Polling Interval

Worker checks for new tasks every **30 seconds**.

### Protection Against Memory Leaks (Added 2026-01-29)

The worker includes these safeguards:
- **Task timeout:** 5 minutes max (`timeout 300`)
- **Stale process cleanup:** Kills `claude --print` older than 30 min every poll
- **Memory logging:** Logs RAM usage each iteration for monitoring

**Check logs for issues:**
```bash
ssh 100.121.76.86 "tail -100 ~/.local/share/claude-worker.log | grep -E 'Memory|timeout|Killed'"
```

## Integration with Claude Code

The `remote` skill at `~/.claude/skills/remote/` provides commands that call these scripts:

```bash
# Skill location
~/.claude/skills/remote/SKILL.md

# Scripts (symlinked to this project)
~/.claude/skills/remote/scripts/delegate.sh -> ~/Projects/remote-tasks/scripts/delegate.sh
~/.claude/skills/remote/scripts/pi-exec.sh -> ~/Projects/remote-tasks/scripts/pi-exec.sh
~/.claude/skills/remote/scripts/mbp-exec.sh -> ~/Projects/remote-tasks/scripts/mbp-exec.sh
~/.claude/skills/remote/scripts/status.sh -> ~/Projects/remote-tasks/scripts/status.sh
```

## Troubleshooting

### Worker Can't Connect to Mac

**Symptoms:** Worker logs show no tasks found, or SSH connection errors

**Root cause:** Pi cannot resolve MagicDNS hostnames (e.g., `matthews-macbook-air`)

**Fix:** Worker must use Tailscale IPs directly:
```bash
# In worker/claude-worker, use IP not hostname:
MAC_HOST="100.79.26.89"  # NOT "matthews-macbook-air"
```

**After fixing:** Sync to Pi and restart:
```bash
cat worker/claude-worker | ssh raspberrypi "cat > ~/.local/bin/claude-worker && chmod +x ~/.local/bin/claude-worker"
ssh raspberrypi "systemctl --user restart claude-worker"
```

### Claude Command Not Found in Worker

**Symptoms:** Worker logs show `timeout: failed to run command 'claude': No such file or directory`

**Root cause:** Claude CLI not in systemd service PATH

**Fix:** Worker must use full path `$HOME/.local/bin/claude` instead of just `claude`
```bash
# In worker execution line:
result=$(timeout "$TASK_TIMEOUT" "$HOME/.local/bin/claude" --print ...)
```

### Delegate Script "No beads database found"

**Symptoms:** `delegate.sh` fails with "Error: no beads database found"

**Root cause:** Script runs `bd` commands, which look for `.beads/` in current directory

**Fix:** Run delegate.sh from home directory where global `.beads/` exists:
```bash
cd ~ && ~/Projects/remote-tasks/scripts/delegate.sh pi "task description"
```

### High Memory Usage on Pi

**Symptoms:** Memory > 70%, swap usage climbing

**Check:**
1. Process list: `ssh 100.121.76.86 "ps aux --sort=-%mem | head -20"`
2. Docker stats: `ssh 100.121.76.86 "docker stats --no-stream"`
3. Stale Claude processes: `ssh 100.121.76.86 "pgrep -af claude"`

**Distinguish worker from stale sessions:**
- Worker uses: `claude --print --model X --dangerously-skip-permissions`
- Stale sessions: `claude` (no `--print` flag) or interactive usage

**Fix:**
```bash
# Kill stale Claude processes (not the worker)
ssh 100.121.76.86 "pkill -f 'claude --model' --exclude 'claude --print'"

# Or kill specific PID
ssh 100.121.76.86 "kill -9 <PID>"
```

**Prevent recurrence:** Worker script includes stale process cleanup (added 2026-01-29)

### Task Not Executing

**Symptoms:** Task created but never runs

**Check:**
1. Worker running: `ssh 100.121.76.86 "systemctl --user status claude-worker"`
2. Task exists: `bd list --assignee=pi --status=open`
3. Worker logs: `ssh 100.121.76.86 "journalctl --user -u claude-worker -f"`
4. Beads synced: `bd sync`

**Common issues:**
- Worker stopped: `ssh 100.121.76.86 "systemctl --user start claude-worker"`
- Task in wrong status: Should be `open`, not `pending`
- Beads not synced: Worker polls local git, run `bd sync`

### No Notifications

**Symptoms:** Task completes but no ntfy notification

**Check:**
1. ntfy server: `curl http://100.121.76.86:8091/claude-tasks`
2. Docker running: `ssh 100.121.76.86 "docker ps | grep ntfy"`
3. Worker can reach ntfy: Check worker logs for curl errors

**Fix:**
```bash
ssh 100.121.76.86
cd ~/Projects/ntfy
docker compose restart
```

### SSH Connection Failed

**Symptoms:** Scripts can't connect to remote machine

**Check:**
1. Tailscale: `tailscale status`
2. Machine reachable: `ping 100.121.76.86`
3. SSH works: `ssh 100.121.76.86 "echo test"`

**Fix:**
- Reconnect Tailscale: `sudo tailscale up`
- Check machine is powered on
- Verify IP hasn't changed: Update `config/machines.json`

### Beads Sync Issues

**Symptoms:** Tasks not appearing on remote machine

**Check:**
1. Git status: `bd sync --status`
2. Git remote: `bd config | grep remote`
3. Network: Can you push/pull from git remote?

**Fix:**
```bash
cd ~/.beads
git pull --rebase
git push
bd sync
```

## Development

### Editing Files on Pi

**Pattern:** Create/edit locally, then upload via SSH pipe
```bash
# Edit file locally first
vim /tmp/my-file.txt

# Upload to Pi
cat /tmp/my-file.txt | ssh 100.121.76.86 "cat > /path/on/pi/file.txt"

# For executable scripts, add chmod
cat /tmp/script.sh | ssh 100.121.76.86 "cat > ~/.local/bin/script.sh && chmod +x ~/.local/bin/script.sh"
```

**Why:** Safer than direct remote editing (preview changes, version control, easier rollback)

### Adding a New Machine

1. Add machine to Tailscale network
2. Install Claude Code on new machine
3. Update `config/machines.json`:
   ```json
   {
     "machines": {
       "newmachine": {
         "ip": "100.x.x.x",
         "name": "Machine Name",
         "hasWorker": false
       }
     }
   }
   ```
4. Create exec script: `scripts/newmachine-exec.sh`
5. Update skill: `~/.claude/skills/remote/SKILL.md`

### Installing Worker on New Machine

1. Copy worker script:
   ```bash
   scp worker/claude-worker <ip>:~/.local/bin/
   ssh <ip> "chmod +x ~/.local/bin/claude-worker"
   ```

2. Update worker's `MACHINE_ID` to match alias:
   ```bash
   ssh <ip> "sed -i '' 's/MACHINE_ID=\"pi\"/MACHINE_ID=\"newmachine\"/' ~/.local/bin/claude-worker"
   ```

3. Install systemd service:
   ```bash
   scp worker/claude-worker.service <ip>:~/.config/systemd/user/
   ssh <ip> "systemctl --user enable --now claude-worker"
   ```

4. Update `config/machines.json`: Set `hasWorker: true`

### Testing Changes

1. **Script changes:** Test locally first, then sync to machines
2. **Worker changes:** Update on Pi, restart service
3. **Config changes:** Ensure JSON is valid: `jq . config/machines.json`

## File Structure

```
remote-tasks/
├── README.md                    # Public documentation
├── CLAUDE.md                    # This file (Claude Code context)
├── MAINTENANCE.md               # Operational changes and optimizations
├── config/
│   └── machines.json            # Machine registry
├── scripts/
│   ├── delegate.sh              # Async task delegation
│   ├── pi-exec.sh               # Direct Pi execution
│   ├── mbp-exec.sh              # Direct MBP execution
│   └── status.sh                # System status
├── worker/
│   ├── claude-worker            # Worker daemon (reference)
│   └── claude-worker.service    # Systemd service (reference)
└── ntfy/
    └── docker-compose.yml       # ntfy config (reference)
```

## Key Design Decisions

### Why Beads over Redis?

- Already installed and used for task tracking
- Git-based sync is more resilient than Redis pub/sub
- No additional infrastructure to maintain
- Persistent history (git log shows all tasks)

### Why Self-Hosted ntfy?

- Privacy: No external service has access to task info
- Simplicity: Single Docker container
- Tailscale-only: Not exposed to internet
- No account/API key needed

### Why Bash Scripts over Python?

- Simpler: 100 LOC vs 400+ LOC
- Fewer dependencies: Just bash, ssh, curl, jq
- More transparent: Easy to understand and modify
- Better integration with shell environment

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Direct SSH execution | < 1s | Depends on command |
| Task delegation | < 2s | Create + sync + notify |
| Worker polling | 30s | Fixed interval |
| Task pickup | 0-30s | Depends on poll timing |
| Beads sync | 1-5s | Depends on git remote |
| ntfy notification | < 1s | Local network |

## Security

- **Tailscale VPN:** All SSH traffic encrypted via WireGuard
- **No public exposure:** ntfy server only accessible via Tailscale
- **SSH keys:** Key-based auth, no passwords
- **Worker permissions:** `--dangerously-skip-permissions` only on trusted Pi
- **No secrets in git:** All config is network-local (Tailscale IPs)

## Maintenance

### Regular Tasks

- **Weekly:** Check worker logs for errors
- **After worker changes:** Always sync live Pi version back to repo: `ssh raspberrypi "cat ~/.local/bin/claude-worker" > worker/claude-worker`
- **Monthly:** Update ntfy Docker image
- **As needed:** Review and close completed Beads tasks

### Monitoring

```bash
# Check all components
./scripts/status.sh

# Worker uptime
ssh 100.121.76.86 "systemctl --user status claude-worker | grep Active"

# ntfy uptime
ssh 100.121.76.86 "docker ps --filter name=ntfy --format '{{.Status}}'"

# Beads health
bd stats
```

## Links

- **Old system:** `~/Projects/claude-mesh.archive/`
- **Implementation plan:** `~/.claude/plans/kind-imagining-frost.md`
- **Skill documentation:** `~/.claude/skills/remote/SKILL.md`
- **Global CLAUDE.md:** `~/.claude/CLAUDE.md` (see "Remote Task System" section)
