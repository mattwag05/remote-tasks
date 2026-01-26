#!/bin/bash
# Execute a command on the M1 MacBook Pro
exec "$(dirname "$0")/ssh-exec.sh" mbp "$*"
