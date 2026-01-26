#!/bin/bash
# Execute a command on the Raspberry Pi
exec "$(dirname "$0")/ssh-exec.sh" pi "$*"
