#!/bin/bash
# Context sync - runs via cron every 5 minutes
# Syncs ~/.claude git repository and Beads across machines
# Add to crontab: */5 * * * * ~/.claude/sync-cron.sh >> ~/.claude/sync.log 2>&1

cd ~/.claude || exit 1

# Pull with rebase to avoid merge commits
git pull --rebase origin main 2>/dev/null

# Push any local changes
git push origin main 2>/dev/null

# Also sync beads task state
bd sync 2>/dev/null

exit 0
