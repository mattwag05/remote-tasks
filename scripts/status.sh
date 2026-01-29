#!/bin/bash
# Check status of all machines and pending tasks

echo "=== Machine Status ==="
echo ""

echo "Raspberry Pi (raspberrypi):"
if ssh -o ConnectTimeout=3 raspberrypi "uptime" 2>/dev/null; then
    echo "  ✓ Online"
else
    echo "  ✗ Offline"
fi
echo ""

echo "M1 MacBook Pro (katies-macbook-pro):"
if ssh -o ConnectTimeout=3 matthewwagner@katies-macbook-pro.tail4902cc.ts.net "uptime" 2>/dev/null; then
    echo "  ✓ Online"
else
    echo "  ✗ Offline"
fi
echo ""

echo "=== Pending Remote Tasks ==="
bd list --status=pending --json 2>/dev/null | jq -r '.[] | select(.assignee == "pi" or .assignee == "mbp" or .assignee == "air") | "  [\(.assignee)] \(.title)"' || echo "  No pending tasks"

echo ""

echo "=== In Progress Remote Tasks ==="
bd list --status=in_progress --json 2>/dev/null | jq -r '.[] | select(.assignee == "pi" or .assignee == "mbp" or .assignee == "air") | "  [\(.assignee)] \(.title)"' || echo "  No tasks in progress"
