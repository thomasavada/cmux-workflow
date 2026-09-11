#!/usr/bin/env bash
# Wait until every named Orca lane has finished its turn, then exit 0.
#
# WHY THIS EXISTS, AND WHY IT IS NOT lane-watch.sh
# -----------------------------------------------
# The cmux watcher reads `agentLifecycle == "idle"` out of cmux's own turn-hook
# session store. That is a recorded fact, so it cannot lie. Orca has no such
# store exposed to the CLI, and its nearest equivalent — `orca terminal wait
# --for tui-idle` — DOES lie: it reports idle while a lane is still mid-turn.
# Measured repeatedly; four false "settled" reports in one session.
#
# WHAT THE SIGNAL IS — AND THE ONE THAT LOOKED RIGHT AND WASN'T
# -------------------------------------------------------------
# The obvious candidate is codex's completed-turn footer:
#
#     ─ Worked for 27m 57s ────────────────────────────────────────────
#
# Do NOT use it alone. Measured: that footer is printed for long multi-step
# turns and NOT for short ones. A one-shot turn finishes like this, with no
# footer anywhere on screen:
#
#     • READY
#     › Ask Codex to do anything
#
# A watcher keyed on the footer therefore hangs forever on exactly the lanes
# that finish fastest. (Found by testing this script against a real lane, after
# it had already been written the wrong way.)
#
# So the state is read off the input box, which is always rendered:
#
#   BUSY     screen contains "esc to interrupt"  — covers "Working (3s …)" and
#            "Waiting for background terminal (1m 05s …)"
#   IDLE     screen contains the "Ask Codex to do anything" prompt, and no BUSY
#
# Both are positive presence checks on the LIVE screen (`--screen`), not on
# scrollback, so stale history cannot satisfy them.
#
# THE ALREADY-IDLE TRAP
# ---------------------
# A terminal sitting at its prompt before dispatch is idle by this test, and a
# naive watcher settles instantly. So a lane must be seen BUSY at least once
# before it may be called finished — with `lastOutputAt` advancing past arm time
# as the tiebreaker for a lane that finished between two polls.
# Arm this in the same turn you dispatch.
#
# Usage:
#   orca-lane-watch.sh --handles term_aaa,term_bbb [--timeout 3600] [--interval 30]
#   orca-lane-watch.sh --auto [...]        # every codex terminal in this worktree
#
# Exit: 0 all lanes finished · 2 timed out · 3 a lane's terminal disappeared
set -euo pipefail

TIMEOUT=3600
INTERVAL=30
HANDLES=""
AUTO=0

while [ $# -gt 0 ]; do
  case "$1" in
    --handles)  HANDLES="${2:-}"; shift 2 ;;
    --timeout)  TIMEOUT="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --auto)     AUTO=1; shift ;;
    -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

# Resolve the CLI once. On Linux a bare `orca` is the GNOME screen reader and
# would start speech on the user's machine — never fall through to it there.
resolve_orca() {
  if [ -n "${ORCA_CLI_COMMAND:-}" ]; then printf '%s' "$ORCA_CLI_COMMAND"; return; fi
  if [ -n "${ORCA_DEV_REPO_ROOT:-}" ] && command -v orca-dev >/dev/null; then
    printf 'orca-dev'; return
  fi
  if [ "$(uname -s)" = "Linux" ]; then
    if command -v orca-ide >/dev/null; then printf 'orca-ide'; return; fi
    echo "refusing to run bare 'orca' on Linux (that is the screen reader)." >&2
    echo "set ORCA_CLI_COMMAND or install orca-ide." >&2
    exit 64
  fi
  printf 'orca'
}
ORCA="$(resolve_orca)"

# stderr is deliberately NOT suppressed anywhere in this script. A wrong flag
# (`send-text` for `send`, `--lines` for `--limit`) fails loudly or not at all;
# hiding it turns a typo into "the lane never started".
list_json() { "$ORCA" terminal list --json; }

if [ "$AUTO" = "1" ]; then
  HANDLES="$(list_json | python3 -c '
import json,sys,os
cwd = os.getcwd()
out = []
for t in json.load(sys.stdin)["result"]["terminals"]:
    if t.get("agentIdentity") != "codex":
        continue
    if t.get("worktreePath") and not cwd.startswith(t["worktreePath"]):
        continue
    out.append(t["handle"])
print(",".join(out))')"
  [ -n "$HANDLES" ] || { echo "no codex lanes found in $(pwd)" >&2; exit 3; }
  echo "auto-discovered lanes: $HANDLES"
fi

[ -n "$HANDLES" ] || { echo "nothing to watch: pass --handles or --auto" >&2; exit 64; }

# busy | idle | unknown — read off the live input box, never scrollback.
lane_state() {
  local screen
  screen="$("$ORCA" terminal read --terminal "$1" --screen --limit 400)"
  if printf '%s' "$screen" | grep -q 'esc to interrupt'; then
    printf 'busy'
  elif printf '%s' "$screen" | grep -q 'Ask Codex to do anything'; then
    printf 'idle'
  else
    printf 'unknown'
  fi
}

last_output_at() {
  "$ORCA" terminal list --json | HANDLE="$1" python3 -c '
import json, os, sys
h = os.environ["HANDLE"]
for t in json.load(sys.stdin)["result"]["terminals"]:
    if t["handle"] == h:
        print(t.get("lastOutputAt") or 0); break
else:
    print(-1)'
}

STATE="$(mktemp -d)"
trap 'rm -rf "$STATE"' EXIT

IFS=',' read -r -a LANES <<< "$HANDLES"
for h in "${LANES[@]}"; do
  lo="$(last_output_at "$h")"
  [ "$lo" = "-1" ] && { echo "lane $h does not exist" >&2; exit 3; }
  printf '%s' "$lo" > "$STATE/$h.armed"
  printf '0'        > "$STATE/$h.seenbusy"
  echo "  armed $h (state=$(lane_state "$h"))"
done

START=$(date +%s)
ROUND=0
while :; do
  ROUND=$((ROUND + 1))
  DONE=1
  LINE=""
  for h in "${LANES[@]}"; do
    st="$(lane_state "$h")"
    [ "$st" = "busy" ] && printf '1' > "$STATE/$h.seenbusy"

    # Idle alone is not enough: a lane parked at its prompt before dispatch is
    # idle too. It must have been seen busy, or have produced output since we
    # armed — which is how a lane that finishes between two polls still counts.
    finished=0
    if [ "$st" = "idle" ]; then
      if [ "$(cat "$STATE/$h.seenbusy")" = "1" ]; then
        finished=1
      elif [ "$(last_output_at "$h")" -gt "$(cat "$STATE/$h.armed")" ]; then
        finished=1
      fi
    fi

    if [ "$finished" = "1" ]; then
      LINE="$LINE ${h:0:14}=done"
    else
      LINE="$LINE ${h:0:14}=$st"
      DONE=0
    fi
  done

  ELAPSED=$(( $(date +%s) - START ))
  echo "  round $ROUND (${ELAPSED}s):$LINE"

  [ "$DONE" = "1" ] && { echo "ALL LANES FINISHED"; exit 0; }
  [ "$ELAPSED" -ge "$TIMEOUT" ] && { echo "TIMEOUT after ${ELAPSED}s" >&2; exit 2; }
  sleep "$INTERVAL"
done
