#!/usr/bin/env bash
# Ends the nested test session started by run-nested-host.sh (by environment, not by name).
pids=()
for p in /proc/[0-9]*; do
  if tr '\0' '\n' < "$p/environ" 2>/dev/null | grep -q '^XDG_RUNTIME_DIR=.*kde-nested-host'; then pids+=("${p#/proc/}"); fi
done 2>/dev/null
(( ${#pids[@]} )) || { echo "no nested session"; exit 0; }
kill "${pids[@]}" 2>/dev/null; sleep 3; kill -9 "${pids[@]}" 2>/dev/null
echo "stopped ${#pids[@]} processes"
