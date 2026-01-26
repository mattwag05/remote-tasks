#!/bin/bash
# Unified SSH execution wrapper for remote machines
# Usage: ssh-exec.sh <machine> <command>

MACHINE="$1"
shift
COMMAND="$*"

if [ -z "$MACHINE" ] || [ -z "$COMMAND" ]; then
    echo "Usage: $0 <machine> <command>" >&2
    echo "Machines: pi, mbp, air" >&2
    exit 1
fi

# Machine IP lookup (Tailscale IPs)
case "$MACHINE" in
    pi)  IP="100.121.76.86" ;;
    mbp) IP="100.88.238.125" ;;
    air) IP="100.114.187.61" ;;
    *)
        echo "Unknown machine: $MACHINE" >&2
        echo "Valid machines: pi, mbp, air" >&2
        exit 1
        ;;
esac

ssh "$IP" "$COMMAND"
