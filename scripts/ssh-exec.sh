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

# Machine hostname lookup (Tailscale MagicDNS)
case "$MACHINE" in
    pi)  HOST="raspberrypi" ;;
    mbp) HOST="matthewwagner@katies-macbook-pro.tail4902cc.ts.net" ;;
    air) HOST="matthews-macbook-air" ;;
    *)
        echo "Unknown machine: $MACHINE" >&2
        echo "Valid machines: pi, mbp, air" >&2
        exit 1
        ;;
esac

ssh "$HOST" "$COMMAND"
