#!/bin/bash
# Delegate a task to a remote machine via Beads

if [[ $# -lt 2 ]]; then
    echo "Usage: delegate.sh <machine> <task description>"
    exit 1
fi

machine="$1"
shift
task="$*"

# Validate machine
if [[ ! "$machine" =~ ^(pi|mbp|air)$ ]]; then
    echo "Error: Unknown machine '$machine'. Valid: pi, mbp, air"
    exit 1
fi

# Create Beads task with the task in the description field (for Claude execution)
echo "Creating task for $machine: $task"
bd create --title="Remote task from $(hostname -s)" --description="$task" --assignee="$machine" --type=task --priority=2

# Sync to remote
bd sync

# Notify via ntfy
curl -s -d "New task delegated to $machine: $task" http://100.121.76.86:8091/claude-tasks >/dev/null

echo "Task created and delegated to $machine"
