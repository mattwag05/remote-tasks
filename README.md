# Remote Tasks

Async cross-machine task delegation system for Claude Code instances running on multiple machines (MacBook Air, M1 MacBook Pro, Raspberry Pi 5) connected via Tailscale VPN.

**Replaces:** Old Redis-based claude-mesh architecture with a simpler, more maintainable approach.

## Overview

This system enables Claude Code instances to:
- Execute synchronous commands on remote machines via SSH
- Delegate async tasks that are queued and executed by worker daemons
- Share results and context via Beads (git-synced task tracking)
- Receive notifications when remote tasks complete

## Architecture

```
Mac creates task → Beads (git sync) → Pi worker polls Beads
                                    ↓
                             Executes with Claude
                                    ↓
                         Updates Beads + sends ntfy
```

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **Scripts** | `scripts/` | SSH execution and task delegation commands |
| **Worker** | `worker/` | Autonomous task worker daemon (runs on Pi) |
| **ntfy** | `ntfy/` | Self-hosted notification server (runs on Pi) |
| **Config** | `config/machines.json` | Machine registry and settings |

## Features

- **3-tier intelligent model selection**: Auto-chooses haiku (simple), sonnet (moderate), or opus (complex) based on task complexity
- **Headless execution**: Worker runs with `--dangerously-skip-permissions` for full autonomy
- **Presence awareness**: Status command shows online/offline machines
- **Git-synced state**: Tasks persist via Beads git sync across all machines
- **Private notifications**: Self-hosted ntfy on Pi (no external services)
- **Context synchronization**: Automated sync of ~/.claude directory every 5 minutes via cron

## Installation

### Prerequisites

- All machines must be connected via Tailscale VPN
- Claude Code installed on all machines
- Beads installed on at least one machine (Mac Air recommended)
- Docker installed on Pi for ntfy server

### Setup

1. **Clone this repository:**
   ```bash
   cd ~/Projects
   git clone git@github.com:mattwag05/remote-tasks.git
   cd remote-tasks
   ```

2. **Install ntfy server on Pi:**
   ```bash
   ssh 100.121.76.86
   cd ~/Projects
   git clone git@github.com:mattwag05/remote-tasks.git
   cd remote-tasks/ntfy
   docker compose up -d
   ```

3. **Install worker daemon on Pi:**
   ```bash
   # Copy worker script
   scp worker/claude-worker 100.121.76.86:~/.local/bin/
   ssh 100.121.76.86 "chmod +x ~/.local/bin/claude-worker"

   # Install systemd service
   scp worker/claude-worker.service 100.121.76.86:~/.config/systemd/user/
   ssh 100.121.76.86 "systemctl --user enable --now claude-worker"
   ```

4. **Link scripts to Claude Code skill:**
   ```bash
   # On Mac Air and MBP
   cd ~/.claude/skills/remote/scripts
   ln -sf ~/Projects/remote-tasks/scripts/delegate.sh .
   ln -sf ~/Projects/remote-tasks/scripts/pi-exec.sh .
   ln -sf ~/Projects/remote-tasks/scripts/mbp-exec.sh .
   ln -sf ~/Projects/remote-tasks/scripts/status.sh .
   ln -sf ~/Projects/remote-tasks/scripts/ssh-exec.sh .
   ln -sf ~/Projects/remote-tasks/scripts/analyze-complexity.sh .
   ln -sf ~/Projects/remote-tasks/scripts/sync-cron.sh .
   ```

5. **Set up context synchronization (optional):**
   ```bash
   # Install sync-cron.sh to ~/.claude
   cp ~/Projects/remote-tasks/scripts/sync-cron.sh ~/.claude/
   chmod +x ~/.claude/sync-cron.sh

   # Add to crontab (syncs every 5 minutes)
   (crontab -l 2>/dev/null; echo "*/5 * * * * ~/.claude/sync-cron.sh >> ~/.claude/sync.log 2>&1") | crontab -
   ```

## Usage

### Direct SSH Execution (Synchronous)

Run commands directly on remote machines and see output immediately:

```bash
# Execute on Pi
~/Projects/remote-tasks/scripts/pi-exec.sh "uptime"

# Execute on MBP
~/Projects/remote-tasks/scripts/mbp-exec.sh "ls ~/Projects"
```

### Async Task Delegation

Create tasks that are queued and executed by remote worker daemons:

```bash
# Delegate to Pi
~/Projects/remote-tasks/scripts/delegate.sh pi "Run tests in eigent project"

# Delegate to MBP
~/Projects/remote-tasks/scripts/delegate.sh mbp "Build and report errors"
```

**How it works:**
1. Task created in Beads with description
2. Beads syncs via git to all machines
3. Worker polls every 30s, finds task
4. Worker analyzes complexity, chooses model (haiku/sonnet/opus)
5. Executes with Claude Code headless mode
6. Results saved to Beads, synced back
7. Notification sent via ntfy

### Check System Status

View machine availability and pending tasks:

```bash
~/Projects/remote-tasks/scripts/status.sh
```

Output:
```
=== Machine Status ===

Raspberry Pi (raspberrypi):
  ✓ Online

M1 MacBook Pro (katies-macbook-pro):
  ✓ Online

=== Pending Remote Tasks ===
  [pi] Remote task from air

=== In Progress Remote Tasks ===
  No tasks in progress
```

## Claude Code Integration

The scripts in this project are designed to be called from the `remote` skill in Claude Code:

```bash
# In Claude Code chat:
# Direct execution
~/.claude/skills/remote/scripts/pi-exec.sh "uptime"

# Async delegation
~/.claude/skills/remote/scripts/delegate.sh pi "task description"

# Status check
~/.claude/skills/remote/scripts/status.sh
```

See `~/.claude/skills/remote/SKILL.md` for skill documentation.

## Worker Management

### Check Worker Status (Pi)

```bash
ssh 100.121.76.86 "systemctl --user status claude-worker"
```

### View Worker Logs

```bash
ssh 100.121.76.86 "journalctl --user -u claude-worker -f"
```

### Restart Worker

```bash
ssh 100.121.76.86 "systemctl --user restart claude-worker"
```

## Configuration

### Machine Registry

Edit `config/machines.json` to add/remove machines or update IPs:

```json
{
  "machines": {
    "pi": {
      "ip": "100.121.76.86",
      "name": "Raspberry Pi 5",
      "hasWorker": true
    }
  },
  "ntfy": {
    "server": "http://100.121.76.86:8091",
    "topic": "claude-tasks"
  }
}
```

### Model Selection Heuristics

The worker automatically chooses the model based on task complexity using `analyze-complexity.sh`:

| Complexity | Model | Triggers |
|------------|-------|----------|
| Complex | **opus** | Keywords: `security`, `architecture`, `algorithm`, `design pattern`, `audit`, `critical`, `sensitive` |
| Moderate | **sonnet** | Keywords: `refactor`, `test`, `debug`, `document`, `migrate`, `complex`, `design`, `implement.*feature`, `optimize` OR word count > 20 |
| Simple | **haiku** | All other tasks |

**Examples:**
- `"Run uptime"` → haiku
- `"Refactor authentication module"` → sonnet
- `"Security audit of API endpoints"` → opus

## Troubleshooting

### Task not executing

1. Check worker is running: `ssh 100.121.76.86 "systemctl --user status claude-worker"`
2. Check worker logs: `ssh 100.121.76.86 "journalctl --user -u claude-worker -f"`
3. Verify task exists: `bd list --assignee=pi --status=open`
4. Ensure Beads is synced: `bd sync`

### No notifications

1. Check ntfy server: `curl http://100.121.76.86:8091/claude-tasks`
2. Verify Docker container: `ssh 100.121.76.86 "docker ps | grep ntfy"`
3. Check ntfy logs: `ssh 100.121.76.86 "docker logs ntfy"`

### SSH connection issues

1. Verify Tailscale: `tailscale status`
2. Check machine is online: `ping 100.121.76.86`
3. Test SSH: `ssh 100.121.76.86 "echo test"`

## Comparison with Old System

| Aspect | Claude Mesh (Old) | Remote Tasks (New) |
|--------|-------------------|-------------------|
| Infrastructure | Redis server | ntfy (Docker) |
| Dependencies | Python, redis-py | Bash, SSH, curl |
| Task tracking | Custom Redis schema | Beads (git-synced) |
| Notifications | Redis pub/sub | Self-hosted ntfy |
| Context sync | Redis keys | Git sync |
| Lines of code | ~400+ | ~100 |
| Setup complexity | High | Low |
| Reliability | Single point of failure | Distributed, resilient |

## License

MIT

## Author

Matthew Wagner (mattwag05)

Built with Claude Code
