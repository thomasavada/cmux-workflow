#!/usr/bin/env bash
# Probe each cmux pane: is it sitting at a SHELL (idle) or is a process holding it (busy)?
#
# Why this is needed: `cmux send` sends KEYSTROKES, not commands. If a codex session is still
# running, the new command is typed into its input box and NEVER executes — no error, no signal.
# Inferring from mtime cannot distinguish "thinking" from "the command fell into the void".
# The only certain method is to make the shell prove it is listening.
#
# Usage:  lane-health.sh            → probe every pane
#         lane-health.sh 169 170    → only specific surfaces
set -uo pipefail

DIR="${TMPDIR:-/tmp}/cmux-lane-probe"
mkdir -p "$DIR"
WAIT="${LANE_PROBE_WAIT:-3}"

# The pane belonging to THIS calling session. Never probe it: `cmux send` types keystrokes, so
# it would type the command into the user's own input box. That happened once already.
SELF=$(cmux identify --json 2>/dev/null | grep -o '"surface_ref"[^,]*' | grep -o '[0-9]\+' | head -1)

surfaces=()
if [ $# -gt 0 ]; then
  surfaces=("$@")
else
  while read -r pane; do
    s=$(cmux list-pane-surfaces --pane "$pane" 2>/dev/null | grep -o 'surface:[0-9]*' | head -1)
    s="${s#surface:}"
    [ -n "$s" ] && [ "$s" != "$SELF" ] && surfaces+=("$s")
  done < <(cmux list-panes 2>/dev/null | grep -o 'pane:[0-9]*')
fi

[ ${#surfaces[@]} -eq 0 ] && { echo "no panes found"; exit 0; }

stamp=$(date +%s)
for id in "${surfaces[@]}"; do
  rm -f "$DIR/$id.$stamp"
  cmux send --surface "surface:$id" "touch $DIR/$id.$stamp" >/dev/null 2>&1
  cmux send-key --surface "surface:$id" Enter >/dev/null 2>&1
done

sleep "$WAIT"

idle=0
for id in "${surfaces[@]}"; do
  if [ -f "$DIR/$id.$stamp" ]; then
    printf "  surface:%-5s IDLE  — sitting at a shell, no lane running\n" "$id"
    idle=$((idle + 1))
    rm -f "$DIR/$id.$stamp"
  else
    printf "  surface:%-5s NOT LISTENING — either a process holds it, or the surface is STUCK\n" "$id"
  fi
done

echo
if [ "$idle" -gt 0 ]; then
  echo "→ $idle pane(s) idle. If a lane should be working there, its command never ran —"
  echo "  close the pane (cmux close-surface --surface surface:N), create a new one, send again."
else
  echo "→ No pane answered. TWO possibilities, distinguished with ps:"
  echo "   a) a real process is running  → pgrep finds it, CPU > 0  → leave it alone"
  echo "   b) the surface is STUCK       → pgrep finds nothing new  → close it, create a new pane"
  echo
  echo "   Stuck surface: after a codex session exits, cmux still accepts 'send' and returns OK"
  echo "   but nothing reads keystrokes any more. A new pane always accepts — that is the test."
fi
