#!/usr/bin/env bash
# Read-only audit of every cmux lane: RUNNING, DONE, BLOCKED, DEAD, or EMPTY?
#
# This is the RECOVERY tool — for when you dispatched lanes and never armed a watcher, or
# came back to a session with no idea what state anything is in. It answers the question
# `lane-health.sh` cannot: "has this lane FINISHED?"
#
# 🔴 It NEVER sends keystrokes. `lane-health.sh` types `touch <file>` into panes to make the
# shell prove it is listening — which once typed into the user's own input box, and which
# still cannot tell "done" from "busy". Everything here is observation only.
#
# ── Where the truth lives ────────────────────────────────────────────────────────────────
# cmux installs turn hooks into codex/grok/claude and maintains a session store at
#   ~/.cmuxterm/<agent>-hook-sessions.json
# keyed by session, each entry carrying `surfaceId`, `pid`, `transcriptPath`, `updatedAt`
# and — the field that matters — `agentLifecycle`: running · idle · needsInput · unknown.
# `idle` means THE TURN ENDED. That is a fact recorded by the agent's own Stop hook, not an
# inference, and it costs one file read.
#
# Three worse signals were measured and rejected on 2026-08-13:
#   · `pgrep -x codex` — counts every codex on the machine; its baseline drifted 6 → 8 → 5
#     as other projects opened and closed their own lanes.
#   · processes under `surface:N` in `cmux top` — codex does NOT attach there (it hangs off a
#     workspace-level `tag:codex.<session>` bucket), so three lanes visibly mid-turn showed
#     nothing but `zsh`/`bash`. A liveness check built on this calls working lanes dead.
#   · `cmux events` — correct, but it is a LIVE STREAM: `--limit N` blocks until N events
#     arrive, so every call needs a timeout wrapper. The store gives the same answer offline.
#
# Usage:  lane-status.sh                       → the caller's workspace
#         lane-status.sh --all                 → every workspace
#         lane-status.sh --workspace workspace:5
#         lane-status.sh --json                → machine-readable
set -uo pipefail

WS_ARG=""; ALL=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS_ARG="$2"; shift 2 ;;
    --all)       ALL=1; shift ;;
    --json)      JSON=1; shift ;;
    -h|--help)   sed -n '2,36p' "$0"; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v cmux    >/dev/null || { echo "cmux not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }

# Without the turn hooks there is no session store, and every lane would be reported EMPTY —
# a wrong answer that looks like a real one. Say so instead.
if ! ls "$HOME"/.cmuxterm/*-hook-sessions.json >/dev/null 2>&1; then
  cat <<'MSG'
No cmux agent-hook session store found (~/.cmuxterm/*-hook-sessions.json).

That store is what records each agent's turn state, so without it every lane below would be
reported EMPTY whether or not it is working. Install the hooks first:

    cmux hooks setup           # all detected agents
    cmux hooks setup codex     # or just one

Then re-run. Existing agent sessions must be restarted to pick the hooks up.
MSG
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cmux-lane-status.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cmux identify --json > "$TMP/self.json" 2>/dev/null || echo '{}' > "$TMP/self.json"

# Bare `cmux tree` is NOT scoped to the caller — it returned surfaces from a different
# workspace, so the default view offered to close another project's lanes. Scope it explicitly
# to the caller's own workspace.
CALLER_WS="$(python3 -c '
import json,sys,re
raw=open(sys.argv[1]).read()
try: print((json.loads(raw).get("caller") or {}).get("workspace_ref") or "")
except Exception:
    m=re.search(r"\"workspace_ref\"\s*:\s*\"(workspace:\d+)\"", raw); print(m.group(1) if m else "")
' "$TMP/self.json" 2>/dev/null)"

if   [ "$ALL" = 1 ];       then cmux tree --all --id-format both > "$TMP/tree.txt" 2>/dev/null
elif [ -n "$WS_ARG" ];     then cmux tree --workspace "$WS_ARG" --id-format both > "$TMP/tree.txt" 2>/dev/null
elif [ -n "$CALLER_WS" ];  then cmux tree --workspace "$CALLER_WS" --id-format both > "$TMP/tree.txt" 2>/dev/null
else                            cmux tree --id-format both > "$TMP/tree.txt" 2>/dev/null
fi
[ -s "$TMP/tree.txt" ] || { echo "cmux returned no tree — is the app running?"; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$REPO_ROOT" ]; then
  git -C "$REPO_ROOT" status --porcelain > "$TMP/git.txt" 2>/dev/null
  git -C "$REPO_ROOT" log --oneline -1    > "$TMP/head.txt" 2>/dev/null
fi

JSON="$JSON" python3 - "$TMP" <<'PY'
import json, os, re, sys, glob, time, pathlib

tmp     = pathlib.Path(sys.argv[1])
as_json = os.environ.get("JSON") == "1"
WATCH   = pathlib.Path(os.path.expanduser("~/.cmux-lane-watch"))

# ── roster ───────────────────────────────────────────────────────────────────────────────
# `cmux identify` reports the caller as a REF (`caller.surface_ref` = "surface:393"), not a
# UUID. Reading it as `surface_id` silently yields "" and the caller's own pane is judged like
# a lane — this session showed up in its own report as a RUNNING lane until it was fixed.
self_ref = ""
try:
    self_ref = (json.loads((tmp/"self.json").read_text()).get("caller") or {}).get("surface_ref") or ""
except Exception:
    m = re.search(r'"surface_ref"\s*:\s*"(surface:\d+)"', (tmp/"self.json").read_text())
    self_ref = m.group(1) if m else ""

ws_re  = re.compile(r'workspace (workspace:\d+) ([0-9A-Fa-f-]{36}) "([^"]*)"')
sf_re  = re.compile(r'surface (surface:\d+) ([0-9A-Fa-f-]{36}) \[(\w+)\] "([^"]*)"')
rows, ws_ref, ws_title = [], "", ""
for line in (tmp/"tree.txt").read_text().splitlines():
    m = ws_re.search(line)
    if m: ws_ref, ws_title = m.group(1), m.group(3); continue
    m = sf_re.search(line)
    if m and m.group(3) == "terminal" and m.group(1) != self_ref:
        rows.append(dict(ref=m.group(1), uuid=m.group(2).upper(), title=m.group(4),
                         ws=ws_ref, ws_title=ws_title))

# ── the session store: newest live session per surface ───────────────────────────────────
store = {}   # surface uuid -> entry
for path in glob.glob(os.path.expanduser("~/.cmuxterm/*-hook-sessions.json")):
    agent = os.path.basename(path).replace("-hook-sessions.json", "")
    try:    sessions = json.load(open(path)).get("sessions") or {}
    except Exception: continue
    for e in (sessions.values() if isinstance(sessions, dict) else sessions):
        if not isinstance(e, dict): continue
        sid = (e.get("surfaceId") or "").upper()
        if not sid: continue
        prev = store.get(sid)
        # 311 historical sessions accumulate against reused surfaces — keep only the newest.
        if prev is None or (e.get("updatedAt") or 0) > (prev.get("updatedAt") or 0):
            e = dict(e); e["_agent"] = agent
            # Claude can be EITHER the orchestrating chat or a dispatched lane, and the two need
            # opposite treatment: never close the first, close the second once verified. The
            # store records the sanitized argv, and a dispatched lane is the one that was
            # launched with its model and permission mode pinned (measured 2026-08-13):
            #   orchestrator : claude --dangerously-skip-permissions
            #   lane         : claude --model sonnet --permission-mode bypassPermissions
            args = " ".join(str(a) for a in ((e.get("launchCommand") or {}).get("arguments") or []))
            e["_dispatched"] = ("--model" in args) or ("--permission-mode" in args)
            store[sid] = e

def pid_alive(pid):
    if not pid: return None
    try:    os.kill(int(pid), 0); return True
    except ProcessLookupError: return False
    except PermissionError:    return True
    except Exception:          return None

def ago(ts):
    if not ts: return ""
    d = time.time() - float(ts)
    if d < 90:   return f"{int(d)}s ago"
    if d < 5400: return f"{int(d//60)}m ago"
    return f"{int(d//3600)}h{int((d%3600)//60):02d} ago"

out = []
for r in rows:
    e     = store.get(r["uuid"]) or {}
    kind  = e.get("_agent") or "shell"
    if kind == "claude" and e.get("_dispatched"):
        kind = "claude*"          # * = dispatched as a lane, so it IS closeable once verified
    life  = (e.get("agentLifecycle") or e.get("runtimeStatus") or "").lower()
    alive = pid_alive(e.get("pid"))
    upd   = e.get("updatedAt")

    if not e:
        state, why = "EMPTY", "no session ever recorded — pane is sitting at a shell"
    elif life == "needsinput":
        # 🔴 codex and Claude END A TURN DIFFERENTLY, and taking `needsInput` at face value
        # mislabels every finished Claude lane as blocked (measured 2026-08-13):
        #   codex  finishes → `idle`
        #   Claude finishes → `needsInput`, because its TUI is now sitting at an empty prompt
        # `lastSubtitle` separates the two cases: "Waiting" = the turn ended and it wants your
        # next message; "Permission" = it genuinely cannot proceed without an answer.
        sub = (e.get("lastSubtitle") or "").lower()
        if sub.startswith("waiting"):
            state, why = "DONE", f"turn ended {ago(upd)} · sitting at its prompt"
        else:
            hint = f" · {e.get('lastSubtitle')}" if e.get("lastSubtitle") else ""
            state, why = "BLOCKED", f"agent is waiting for an answer ({ago(upd)}){hint}"
    elif life == "running":
        # `running` plus a dead pid is the crash case, and the one that costs work: nothing
        # ever writes `idle` for a process that was killed, so this entry would read RUNNING
        # forever. Silence is indistinguishable from still-working unless the pid is checked.
        state, why = ("RUNNING", f"turn started {ago(upd)}") if alive is not False else \
                     ("DEAD", f"turn started {ago(upd)} but pid {e.get('pid')} is gone")
    elif life == "idle":
        state, why = ("DONE", f"turn ended {ago(upd)}") if alive is not False else \
                     ("DONE", f"turn ended {ago(upd)} · process has exited")
    else:
        state, why = ("RUNNING" if alive else "EMPTY"), f"lifecycle '{life or 'unknown'}'"

    out.append(dict(ref=r["ref"], title=r["title"], ws=r["ws"], ws_title=r["ws_title"],
                    kind=kind, state=state, why=why,
                    armed=(WATCH/f"{r['ref'].replace(':','-')}.watch").exists(),
                    transcript=e.get("transcriptPath") or "", pid=e.get("pid"),
                    age=(time.time() - float(upd)) if upd else None))

if as_json:
    print(json.dumps(out, indent=2)); sys.exit(0)

cur = None
for o in sorted(out, key=lambda x: (x["ws"], int(x["ref"].split(":")[1]))):
    if o["ws"] != cur:
        cur = o["ws"]; print(f'\n{o["ws"]} "{o["ws_title"]}"')
    flag = "" if (o["armed"] or o["kind"] == "claude" or o["state"] != "RUNNING") else "  ⚠ no watcher"
    print(f'  {o["ref"]:<13} {o["kind"]:<7} {o["title"][:24]:<24} {o["state"]:<8} {o["why"]}{flag}')

git_lines = (tmp/"git.txt").read_text().splitlines() if (tmp/"git.txt").exists() else []
head      = (tmp/"head.txt").read_text().strip()     if (tmp/"head.txt").exists() else ""
if git_lines:
    print(f'\nGIT  {len(git_lines)} uncommitted file(s) (HEAD: {head})')
    for l in git_lines[:8]: print(f'       {l}')
    if len(git_lines) > 8:  print(f'       … +{len(git_lines)-8} more')

# Bare `claude` surfaces are excluded from every disposal suggestion: they are the orchestrating
# chat or a teammate, and closing one throws away everything it has read. Idle is not done.
# `claude*` — launched with --model/--permission-mode — was dispatched as a lane and is treated
# like any other lane.
#
# Two more exclusions, both learned by watching --all produce dangerous advice:
#   · EMPTY means no session was ever recorded on that surface — it is a plain shell, not a
#     spent lane. `--all` listed eleven of them across unrelated projects with a close command
#     attached to each. Never advise closing something that was never a lane.
#   · STALE (older than STALE_H) is another workspace's history, not this session's work.
#     `--all` offered to close turns that ended 35 hours ago in a different repo.
STALE_H = 6
def fresh(o): return o["age"] is not None and o["age"] < STALE_H * 3600

lanes   = [o for o in out if o["kind"] != "claude"]
done    = [o for o in lanes if o["state"] == "DONE" and fresh(o)]
stale   = [o for o in lanes if o["state"] == "DONE" and not fresh(o)]
dead    = [o for o in lanes if o["state"] == "DEAD" and fresh(o)]
blocked = [o for o in lanes if o["state"] == "BLOCKED" and fresh(o)]
empty   = []
unarmed = [o for o in lanes if o["state"] == "RUNNING" and not o["armed"]]
cl_done = [o for o in out   if o["kind"] == "claude" and o["state"] == "DONE" and fresh(o)]

print("\nWHAT NEEDS DOING")
if blocked:
    print("  🔴 BLOCKED — waiting for an answer; it cannot get out of this on its own:")
    for o in blocked: print(f'       cmux read-screen --surface {o["ref"]} --lines 40')
if dead:
    print("  🔴 DEAD — started a turn and died mid-way. Its work IS STILL ON DISK:")
    print("       git status → KEEP IT, never `git checkout` → re-brief:")
    for o in dead: print(f'       {o["ref"]} "{o["title"]}"')
if done:
    print("  ✅ DONE — verify → run the gate → commit → and ONLY THEN close:")
    print("     (closing destroys the context; DONE means the turn ended, not that the work is right)")
    for o in done:
        print(f'       {o["ref"]} "{o["title"]}"')
        if o["transcript"]: print(f'           transcript: {o["transcript"]}')
        print(f'           cmux close-surface --surface {o["ref"]}   # after it is committed')
if stale:
    print(f'  ⚪ {len(stale)} lane(s) finished >{STALE_H}h ago (another workspace\'s history) — ignore,')
    print(f'     unless you are deliberately tidying up: {", ".join(o["ref"] for o in stale[:6])}')
if unarmed:
    print("  ⏳ RUNNING with NO watcher — these will finish and nobody will know:")
    print("       lane-watch.sh " + " ".join(o["ref"].split(":")[1] for o in unarmed))
if cl_done:
    print("  💬 Claude session ended its turn — do NOT close it. Idle is not done:")
    print("     if it never reported, nudge it with SendMessage; closing loses everything it read.")
    for o in cl_done: print(f'       {o["ref"]} "{o["title"]}" — {o["why"]}')
if not (blocked or dead or done or unarmed or cl_done):
    print("  — nothing. Every lane is running and every one has a watcher.")
PY
