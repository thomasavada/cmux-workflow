#!/usr/bin/env bash
# Arm a bounded watcher on one or more lanes. Exits when every lane has ENDED ITS TURN, or on
# timeout. How you run it depends on your host, and that is the ONE thing that differs:
#   Claude Code  Bash(run_in_background: true)                  — you are re-invoked on exit
#   grok         run_terminal_command(background: true)          — a notification lands in chat
#   codex        FOREGROUND, and let the call block              — nothing there re-invokes you
# That re-invocation (or the blocking call) is the only mechanism that will ever tell you a lane
# finished. `sleep 60 && check` in the foreground is blocked in Claude Code, and "I'll check back
# later" is not a mechanism anywhere — your turn ends and the lanes run on.
#
# Usage:  lane-watch.sh 440 442
#         lane-watch.sh 440 --timeout-min 90
#         lane-watch.sh --all-running          (every lane lane-status.sh calls RUNNING)
#
# The condition is `agentLifecycle == "idle"` in cmux's own session store, compared against a
# baseline `updatedAt` captured at arm time. That satisfies both rules a cheap condition fails:
#   · it names the deliverable, not its neighbourhood — this surface's own turn, not "some
#     codex somewhere", the way `pgrep -x codex` matches another project's lane;
#   · it compares against the old value instead of testing for presence — the store already
#     holds `idle` from previous turns, and a bare presence test fires instantly on that.
#
# It also exits early on DEATH (`running` + a dead pid): a lane that crashed never writes
# `idle`, so without the pid check it reads as RUNNING forever and silence is
# indistinguishable from still-working.
set -uo pipefail

TIMEOUT_MIN=60; POLL=15; TARGETS=(); ALL_RUNNING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-min) TIMEOUT_MIN="$2"; shift 2 ;;
    --poll)        POLL="$2"; shift 2 ;;
    --all-running) ALL_RUNNING=1; shift ;;
    -h|--help)     sed -n '2,22p' "$0"; exit 0 ;;
    *)             TARGETS+=("${1#surface:}"); shift ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_DIR="$HOME/.cmux-lane-watch"; mkdir -p "$WATCH_DIR"

if [ "$ALL_RUNNING" = 1 ]; then
  while read -r r; do [ -n "$r" ] && TARGETS+=("$r"); done < <(
    bash "$HERE/lane-status.sh" --all --json 2>/dev/null |
    python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print("\n".join(o["ref"].split(":")[1] for o in d
                if o["state"]=="RUNNING" and o["kind"]!="claude"))')
fi
[ ${#TARGETS[@]} -eq 0 ] && { echo "no lanes to watch"; exit 0; }

# ref → surface uuid, once, at arm time
MAP="$(cmux tree --all --id-format both 2>/dev/null |
  python3 -c 'import re,sys
for l in sys.stdin:
    m=re.search(r"surface (surface:\d+) ([0-9A-Fa-f-]{36})",l)
    if m: print(m.group(1).split(":")[1], m.group(2).upper())')"

# One helper does every store read: baseline, poll, and death check.
read -r -d '' PROBE <<'PY'
import json, glob, os, sys
want = {u.upper() for u in sys.argv[1:]}
best = {}
for path in glob.glob(os.path.expanduser("~/.cmuxterm/*-hook-sessions.json")):
    try: sessions = json.load(open(path)).get("sessions") or {}
    except Exception: continue
    for e in (sessions.values() if isinstance(sessions, dict) else sessions):
        if not isinstance(e, dict): continue
        sid = (e.get("surfaceId") or "").upper()
        if sid not in want: continue
        if sid not in best or (e.get("updatedAt") or 0) > (best[sid].get("updatedAt") or 0):
            best[sid] = e
for sid in want:
    e = best.get(sid) or {}
    pid, alive = e.get("pid"), "?"
    if pid:
        try: os.kill(int(pid), 0); alive = "1"
        except ProcessLookupError: alive = "0"
        except Exception:          alive = "1"
    print(sid, (e.get("agentLifecycle") or e.get("runtimeStatus") or "none").lower(),
          f'{e.get("updatedAt") or 0:.0f}', alive)
PY
probe() { python3 -c "$PROBE" "$@"; }

# Parallel indexed arrays and a linear scan, not associative arrays. macOS still ships bash 3.2 at
# /bin/bash, and there `declare -A` fails WITHOUT stopping the script: it prints `declare: -A:
# invalid option`, leaves an ordinary indexed array behind, and execution continues. The surface
# UUID then lands in `BASE[$sid]` as an indexed subscript, which bash evaluates as arithmetic —
# `FE1D186C-BBDD-4EF1-…` becomes a subtraction of unset names and dies under `set -u` with
# `FE1D186C: unbound variable`. Measured 2026-08-14: the watcher exits about a second after it is
# armed, having watched nothing, and its exit is the very wake-up the orchestrator was relying on.
# At three or four lanes a linear scan costs nothing, and this runs on the bash already present.
REFS=(); UUIDS=()
for t in "${TARGETS[@]}"; do
  u="$(echo "$MAP" | awk -v r="$t" '$1==r{print $2}')"
  [ -z "$u" ] && { echo "surface:$t does not exist — skipping"; continue; }
  REFS+=("$t"); UUIDS+=("$u")
done
N=${#REFS[@]}
[ "$N" -eq 0 ] && { echo "no valid lane to watch"; exit 1; }

IDX=-1
find_idx() {                        # sets IDX to the slot holding surface uuid $1, or -1
  local i=0; IDX=-1
  while [ "$i" -lt "$N" ]; do
    [ "${UUIDS[$i]}" = "$1" ] && { IDX="$i"; return; }
    i=$((i+1))
  done
}

BASES=(); STATES=(); i=0
while [ "$i" -lt "$N" ]; do BASES[$i]=0; STATES[$i]=""; i=$((i+1)); done

while read -r sid life upd alive; do
  find_idx "$sid"; [ "$IDX" -ge 0 ] && BASES[$IDX]="$upd"
done < <(probe "${UUIDS[@]}")

i=0
while [ "$i" -lt "$N" ]; do
  printf 'armed_baseline=%s pid=%s\n' "${BASES[$i]}" "$$" > "$WATCH_DIR/surface-${REFS[$i]}.watch"
  i=$((i+1))
done
cleanup() {
  local i=0
  while [ "$i" -lt "$N" ]; do rm -f "$WATCH_DIR/surface-${REFS[$i]}.watch"; i=$((i+1)); done
}
trap cleanup EXIT

echo "WATCHING $N lane(s), timeout ${TIMEOUT_MIN}m:"
i=0
while [ "$i" -lt "$N" ]; do echo "  surface:${REFS[$i]}  (baseline updatedAt ${BASES[$i]})"; i=$((i+1)); done

MAX=$(( TIMEOUT_MIN * 60 / POLL )); n=0; ENDED=0
while [ "$ENDED" -lt "$N" ] && [ "$n" -lt "$MAX" ]; do
  sleep "$POLL"; n=$((n+1))
  while read -r sid life upd alive; do
    find_idx "$sid"; [ "$IDX" -lt 0 ] && continue
    [ -n "${STATES[$IDX]}" ] && continue
    ref="${REFS[$IDX]}"; base="${BASES[$IDX]}"

    if [ "$life" = "idle" ] && [ "$upd" -gt "$base" ]; then
      STATES[$IDX]="DONE"; ENDED=$((ENDED+1))
      echo "surface:$ref  DONE  — turn ended (after ~$((n*POLL))s)"
      rm -f "$WATCH_DIR/surface-$ref.watch"
    elif [ "$life" = "needsinput" ] && [ "$upd" -gt "$base" ]; then
      STATES[$IDX]="BLOCKED"; ENDED=$((ENDED+1))
      echo "surface:$ref  BLOCKED — waiting for an answer, cannot get out on its own (after ~$((n*POLL))s)"
      rm -f "$WATCH_DIR/surface-$ref.watch"
    elif [ "$alive" = "0" ]; then
      STATES[$IDX]="GONE"; ENDED=$((ENDED+1))
      echo "surface:$ref  GONE  — pid died without ever going idle ⇒ crashed mid-turn. Its work IS STILL ON DISK."
      rm -f "$WATCH_DIR/surface-$ref.watch"
    fi
  done < <(probe "${UUIDS[@]}")
done

echo
if [ "$ENDED" -lt "$N" ]; then
  echo "TIMEOUT after $((MAX*POLL))s — still running:"
  i=0
  while [ "$i" -lt "$N" ]; do
    [ -z "${STATES[$i]}" ] && echo "  surface:${REFS[$i]}"
    i=$((i+1))
  done
  echo "TIMEOUT is a result, not a failure. Report it as exactly that."
else
  echo "ALL $N lane(s) have ended their turn."
fi
echo "→ next: lane-status.sh  →  verify → run the gate → commit → close-surface"
