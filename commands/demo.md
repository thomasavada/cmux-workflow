---
description: Guided live demo — spawn a worktree, a workspace, a codex lane and a Claude teammate, watch them finish, then tear it all down
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill
---

A working tour of this plugin. You will **actually** create a git worktree, a cmux workspace, a
codex lane and a Claude teammate, watch them finish through the session store, then remove every
trace. Narrate each step to the user as you go — the point is that they understand the mechanism,
not that a script ran.

## Before you start — ask

This spends tokens, opens panes, and writes a throwaway branch. Say what it will do and get a
yes. Then check the ground:

```bash
command -v cmux codex || echo "missing a prerequisite"
ls ~/.cmuxterm/*-hook-sessions.json >/dev/null 2>&1 || echo "run: cmux hooks setup"
git rev-parse --show-toplevel                      # must be inside a git repo
```

No cmux, no codex, or no session store ⇒ **stop and say which one is missing.** A demo that
half-runs teaches the wrong thing.

## Ground rules while running it

- **Narrate the WHY, one or two sentences per step.** Every step below exists because something
  failed without it; say which.
- **Show the real output**, including anything that refuses. A refusal is the lesson.
- **Never touch the user's existing lanes.** Run `lane-status.sh` first, note what was already
  there, and only ever close surfaces this demo created.
- If a step fails, **stop and explain** rather than pushing on. Then still run teardown.

---

## 1 · Baseline, before anything exists

```bash
pgrep -x codex | wc -l          # remember this number
```

*Why:* after dispatch you check this went **up by one**. Counted afterwards only, "5" tells you
five codex processes exist somewhere on the machine — most belonging to other projects.

## 2 · A worktree, outside the repo tree

```bash
REPO="$(git rev-parse --show-toplevel)"
WT="$HOME/cmux/worktrees/$(basename "$REPO")/demo-$(date +%H%M%S)"
mkdir -p "$(dirname "$WT")"
git worktree add "$WT" -b chore/cmux-demo
```

*Why outside:* nesting worktrees inside the repo makes every scan-the-whole-tree tool find the
same config several times. One CLI refused to start over exactly that (§1.1).

Say plainly that a real worktree would now need the project's setup step — gitignored config,
`node_modules`, build output — and that this demo skips it because the lane only writes one file.

## 3 · A workspace for it

```bash
cmux new-workspace --name "cmux-demo" --cwd "$WT" --focus false
```

Point out the sidebar entry. This is what §1.1a makes you close **before** deleting the directory.

## 4 · A named pane

```bash
cmux new-split right --workspace workspace:<W>       # → note the surface ref it prints
cmux rename-tab --workspace workspace:<W> --surface surface:<N> "DEMO-1 hello"
```

🔴 **Carry `--workspace` on every call to a surface outside the caller's workspace** — rename,
send, send-key, read-screen. Without it the rename answers `not_found: Tab not found`, because
`--surface` is resolved inside the caller's own workspace *(measured 2026-08-13)*.

*Why the name:* `new-split` has no name flag and surface refs get renumbered. With three panes
open, an unnamed one is a number you have to keep in your head.

## 5 · Probe — make the shell prove it is listening

```bash
cmux send --workspace workspace:<W> --surface surface:<N> "touch $WT/.demo-probe"
cmux send-key --workspace workspace:<W> --surface surface:<N> Enter
sleep 1; ls "$WT/.demo-probe"          # the file MUST appear
```

*Why:* `cmux send` types **keystrokes** and returns `OK` even when nothing reads them. A probe
must leave a trace on disk; `pwd` is worthless because its output stays inside the pane.

## 6 · Write the brief, then dispatch

Write `$WT/BRIEF-demo.md` with a task small enough to finish in a minute — e.g. *create
`hello-from-lane.md` containing one sentence, then report the file list and stop.* Include the
sentence that a lane in a worktree **cannot commit** and must not try.

```bash
cmux send --workspace workspace:<W> --surface surface:<N> 'codex -s workspace-write -a never --strict-config -m gpt-5.6-sol -c model_reasoning_effort=low "Lane DEMO-1. Read BRIEF-demo.md and follow it."'
cmux send-key --workspace workspace:<W> --surface surface:<N> Enter
sleep 3; pgrep -x codex | wc -l        # MUST be baseline + 1
```

*Why `-a never`:* without it codex stops at the first approval prompt in a pane nobody is
watching, and looks exactly like a lane that is thinking.

## 7 · Read the screen

```bash
cmux read-screen --workspace workspace:<W> --surface surface:<N> --lines 20
```

*Why:* a live process is not a working lane. A first run in a new worktree can sit on
`Do you trust the contents of this directory?`, which `-a never` does not suppress. Send `Enter`
if you see it.

## 8 · A Claude teammate, in parallel

Spawn one with the `Agent` tool, `run_in_background: true`, model `sonnet`, with a small
read-only question about the repo. Say why this is a teammate and not a lane: judgment and prose,
no file boundaries.

## 9 · The state of everything

```bash
ROOT="${CLAUDE_PLUGIN_ROOT}"
bash "$ROOT/skills/cmux-orchestration/lane-status.sh" --all
```

Read the output aloud: the demo lane is `RUNNING` and flagged **no watcher**. A one-file task can
finish before you get here — if it already says `DONE`, say so and skip step 10 rather than
pretending to watch something that has stopped. Point at the
`claude` rows and say those are never closed by this tool.

## 10 · Arm the watcher

```bash
bash "$ROOT/skills/cmux-orchestration/lane-watch.sh" <N> --timeout-min 5
```

Run it with `Bash(run_in_background: true)`. *Why:* the harness re-invokes you when a background
command **exits** — that is the only mechanism that will tell you a lane finished. Show that
`lane-status.sh` now prints `armed` for that surface.

## 11 · When it finishes

`lane-status.sh` flips it to `DONE`, sourced from `agentLifecycle: idle` in cmux's own store —
a fact written by the agent's Stop hook, not a guess from `pgrep`.

Then show the thing people get wrong:

```bash
git -C "$WT" status --porcelain        # the lane's work, UNCOMMITTED by design
```

A worktree lane cannot commit: `.git` is a file pointing at the main repo, whose object store
sits outside the sandbox's writable root. The work is on disk and nowhere else.

## 12 · Teardown — and let it refuse

```bash
cmux close-workspace --workspace <ref>     # workspace first, or it lingers pointing at nothing
git worktree remove "$WT"                  # EXPECT THIS TO REFUSE
```

**It will refuse**, because the lane left untracked files. Show the error verbatim:

```
fatal: '<path>' contains modified or untracked files, use --force to delete it
```

*This is the most important moment of the demo.* That refusal is the guard standing between
routine cleanup and deleting a lane's entire output. `--force` would delete it permanently, and a
worktree is where that hurts most because nothing was committed.

Harvest first, then remove:

```bash
cat "$WT/hello-from-lane.md"               # this is what --force would have destroyed
git worktree remove --force "$WT"          # only now, and only because we read it first
git branch -d chore/cmux-demo              # plain -d: see below
git worktree prune
```

⚠️ **`-d` succeeds here, and the reason is worth saying out loud:** the lane could not commit, so
the branch is still exactly at its base and git considers it merged. The safety net you would
meet on a real feature branch — `error: the branch is not fully merged` — does **not** fire in
this demo. Say so, rather than letting the user conclude `-d` is always safe.

⚠️ **Do not close the lane's surface afterwards.** `cmux close-workspace` already took it with
the workspace, and `cmux close-surface --surface <N>` then answers `Surface ref not found`.
Closing the workspace is the single teardown step.

Removing a worktree never deletes its branch — that is why the branch line exists at all.

## 13 · Verify nothing was left behind

```bash
git worktree list                      # demo worktree gone
git branch --list 'chore/cmux-demo'    # empty
cmux list-panes                        # only what existed before step 4
bash "$ROOT/skills/cmux-orchestration/lane-status.sh" --all
```

Compare against the note you took in "Ground rules". Any difference is yours to clean up.

## Close with what they can now do

Four sentences, no more: `/cmux-workflow:lanes` for state at any time; `lane-watch.sh` armed at
dispatch so nothing finishes unnoticed; `cmux-orchestration` §2 for what a brief must contain;
`cmux-screen-layout` before the third pane.
