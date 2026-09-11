#!/usr/bin/env bash
# Audit Orca lanes you may have forgotten to watch.
#
# Answers the three questions that actually come up — "are the lanes done?",
# "which pane is which?", "is it safe to close?" — without opening the UI.
#
# Usage:
#   orca-lane-status.sh              # codex lanes in this worktree
#   orca-lane-status.sh --all        # every Orca terminal, any worktree
#   orca-lane-status.sh --json       # machine-readable
#
# State is read off the live input box, the same way orca-lane-watch.sh does it:
# "esc to interrupt" present = busy; the "Ask Codex to do anything" prompt with
# no busy marker = idle. Never `tui-idle` (it reports idle mid-turn), and never
# the "Worked for Xm Ys" footer — that is only printed for long turns, so a
# short turn finishes without one. See orca-lane-watch.sh for the measurements.
#
# Unlike the watcher, this is a point-in-time read with no arm-time baseline, so
# `idle` here means "not working right now", not "finished the job you gave it".
set -euo pipefail

ALL=0
AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     ALL=1; shift ;;
    --json)    AS_JSON=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

resolve_orca() {
  if [ -n "${ORCA_CLI_COMMAND:-}" ]; then printf '%s' "$ORCA_CLI_COMMAND"; return; fi
  if [ -n "${ORCA_DEV_REPO_ROOT:-}" ] && command -v orca-dev >/dev/null; then
    printf 'orca-dev'; return
  fi
  if [ "$(uname -s)" = "Linux" ]; then
    if command -v orca-ide >/dev/null; then printf 'orca-ide'; return; fi
    echo "refusing to run bare 'orca' on Linux (that is the screen reader)." >&2
    exit 64
  fi
  printf 'orca'
}
ORCA="$(resolve_orca)"

TERMS="$("$ORCA" terminal list --json)"

# Select first, so the (slow) per-lane screen read runs only on real candidates.
SELECTED="$(printf '%s' "$TERMS" | ALL="$ALL" python3 -c '
import json, os, sys
cwd, all_ = os.getcwd(), os.environ.get("ALL") == "1"
for t in json.load(sys.stdin)["result"]["terminals"]:
    if not all_:
        if t.get("agentIdentity") != "codex":
            continue
        wp = t.get("worktreePath")
        if wp and not cwd.startswith(wp):
            continue
    print("\t".join([
        t["handle"],
        (t.get("title") or "")[:22],
        t.get("agentIdentity") or "-",
        str(t.get("lastOutputAt") or 0),
    ]))')"

[ -n "$SELECTED" ] || { echo "no lanes found$([ "$ALL" = 1 ] || echo " in $(pwd)")"; exit 0; }

NOW_MS=$(( $(date +%s) * 1000 ))
ROWS=""
while IFS=$'\t' read -r handle title identity last; do
  [ -n "$handle" ] || continue
  screen="$("$ORCA" terminal read --terminal "$handle" --screen --limit 400)"
  if printf '%s' "$screen" | grep -q 'esc to interrupt'; then
    state=busy
  elif printf '%s' "$screen" | grep -q 'Ask Codex to do anything'; then
    state=idle
  else
    state=unknown
  fi
  idle_s=$(( (NOW_MS - last) / 1000 ))
  ROWS="${ROWS}${handle}\t${title}\t${identity}\t${state}\t${idle_s}\n"
done <<< "$SELECTED"

if [ "$AS_JSON" = "1" ]; then
  printf '%b' "$ROWS" | python3 -c '
import json, sys
out = []
for line in sys.stdin:
    if not line.strip():
        continue
    h, t, i, s, idle = line.rstrip("\n").split("\t")
    out.append({"handle": h, "title": t, "agent": i,
                "state": s, "idleSeconds": int(idle)})
print(json.dumps(out, indent=2))'
  exit 0
fi

printf '  %-42s %-22s %-8s %-9s %s\n' HANDLE TITLE AGENT STATE QUIET
printf '%b' "$ROWS" | while IFS=$'\t' read -r h t i s idle; do
  [ -n "$h" ] || continue
  printf '  %-42s %-22s %-8s %-9s %ss\n' "$h" "$t" "$i" "$s" "$idle"
done

echo
echo "  idle = not working right now. It does NOT mean the brief is done —"
echo "  a lane that stopped to ask a question is idle too. Read the screen."
echo "  Before closing: a codex lane CANNOT commit, so its work is sitting in"
echo "  the working tree. Check 'git status' and harvest it first — closing the"
echo "  pane discards anything uncommitted."
