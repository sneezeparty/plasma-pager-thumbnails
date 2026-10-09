#!/usr/bin/env bash
# Runs a command inside the running nested session:
#   distrobox enter kde-dev -- ~/kde/nested-exec.sh konsole
source "$HOME/kde/nested-home/env.sh"
exec "$@"
