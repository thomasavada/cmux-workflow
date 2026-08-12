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

## Load the skills first — this file does not restate them

This command is a **script for a demo**, not a second copy of the rules. Before step 1, load:

| Skill | What it owns here |
|---|---|
| `cmux-workflow:cmux-screen-layout` | **where the panes go.** Read it BEFORE the second pane |
| `cmux-workflow:cmux-orchestration` | §5.0 the five dispatch steps · §2 what a brief needs · §1.1a teardown |
| `cmux-workflow:orchestration-loop` | why a background watcher is the only mechanism that notifies you |

🔴 **The layout skill is not optional garnish — skipping it is how this demo failed on its first
real run** *(2026-08-13)*. Four lanes were opened with `new-split right` four times, which is the
exact anti-pattern that skill opens with: the result was five columns roughly 40 characters wide,
codex's box drawing wrapped into soup, and nothing on screen could be read — by the presenter or
the audience. The lanes were all working perfectly. **A demo nobody can read is a failed demo**,
and the fix costs one command.

Follow that skill's rule for the lane count you are actually running, and if the panes still come
out unreadable, **stop and fix the layout before dispatching anything else.** Do not push on.

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

## 3 · A group, then a workspace inside it

Everything this demo creates goes in **one throwaway group**, so nothing lands at the top of the
user's rail and teardown is a single command:

```bash
G=$(cmux workspace-group create --name "demo" | grep -o 'workspace_group:[0-9]*')
cmux workspace create --name "cmux-demo" --cwd "$WT" --group "$G" --focus false
```

*Why a group of its own rather than the caller's group:* a demo is disposable as a unit. Real lane
work inherits the caller's group instead — that rule, and the resolver for it, live in
`cmux-orchestration` §1.1.

⚠️ Creating a group also creates an **anchor** workspace to own it, so expect one more row than
you made. Point at the collapsible group header: that is the demo, contained.

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
sleep 4; ls "$WT/.demo-probe"          # the file MUST appear
```

*Why:* `cmux send` types **keystrokes** and returns `OK` even when nothing reads them. A probe
must leave a trace on disk; `pwd` is worthless because its output stays inside the pane.

⚠️ **Give the shell time to start, or you get a FALSE negative** *(measured 2026-08-13)*: a probe
checked ~2s after `new-split` reported failure while the screen showed the command had run — the
shell was still printing `Last login`. The skill's advice for a failed probe is "close the pane
and recreate it", which would have thrown away a perfectly healthy pane. Wait ~4s, and if it
fails, **read the screen before concluding anything**.

## 6 · Four lanes, four different jobs

One lane proves the plumbing. **Four lanes show what the plumbing is for** — so give each one a
different shape, and let the audience watch them finish at different times.

| Lane | Agent | Why this one is in the demo |
|---|---|---|
| `DEMO-1 hello` | codex, `--effort low` | the fastest possible lane. Finishes in seconds, so the first `DONE` lands while you are still talking |
| `DEMO-2 review` | **claude, `--model sonnet`** | proves a lane is not "a codex thing". Opus orchestrates, Sonnet does the work |
| `DEMO-3 security` | codex, `--effort xhigh`, read-only | effort chosen by **blast radius**, not by how hard the task feels |
| `DEMO-4 implement` | codex in the **worktree** | the only one that writes code — and the one that cannot commit |

Write each brief as a file first; never stuff it into the `send` string, which types through a
simulated keyboard. Keep every brief to one small deliverable and end each with *"report the file
list, then stop."*

**Dispatch pattern — identical for all four, except the agent line.** Take the split direction
from `cmux-screen-layout`, not from this file; with four lanes it is **not** four `new-split
right`:

```bash
cmux new-split <direction per the layout skill> --workspace workspace:<W>
cmux rename-tab --workspace workspace:<W> --surface surface:<N> "DEMO-2 review"
sleep 4                                        # let the shell finish starting — see §5 below
cmux send     --workspace workspace:<W> --surface surface:<N> "<the agent command>"
cmux send-key --workspace workspace:<W> --surface surface:<N> Enter
```

The two agent lines, and the flag that matters in each:

```bash
# codex — -a never is what stops it halting on an approval nobody is watching
codex -s workspace-write -a never --strict-config -m gpt-5.6-sol -c model_reasoning_effort=low "Lane DEMO-1. Read BRIEF-1.md and follow it."

# claude — --permission-mode acceptEdits is NOT the equivalent: it auto-accepts EDITS but still
# stops for every Bash command. Measured 2026-08-13: the lane sat on "Do you want to proceed?"
claude --model sonnet --permission-mode bypassPermissions "Lane DEMO-2. Read BRIEF-2.md and follow it."
```

🔴 **Say that codex/Claude difference out loud.** It is the single most useful thing an audience
takes away from this section, and it is invisible until a lane hangs.

⚠️ **Cost is real, and Claude lanes bill against the same weekly quota as the chat driving them.**
Check before you run four lanes in front of people; the Claude TUI footer prints the percentage
used. Cut to two lanes (`hello` + `review`) if the budget is tight — the lesson survives.

## 7 · Read every screen

```bash
cmux read-screen --workspace workspace:<W> --surface surface:<N> --lines 20
```

*Why:* a live process is not a working lane. A first run in a new worktree can sit on
`Do you trust the contents of this directory?`, which `-a never` does not suppress.

## 8 · Pin the workspace while they run

```bash
cmux workspace-action --action pin       --workspace workspace:<W>
cmux workspace-action --action set-color --workspace workspace:<W> --color "#4C8DFF"
```

*Why here:* with four lanes running, this is the row you keep coming back to. Pinning holds it at
the top of the rail while everything else moves around it. It also sets up the teardown lesson in
§12, because **a pinned workspace refuses to close**.

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
cmux workspace-action --action unpin --workspace <ref>   # §8 pinned it — this is REQUIRED
cmux workspace-group delete "$G" --close-workspaces      # the group AND every member, one command
git worktree remove "$WT"                                # EXPECT THIS TO REFUSE
```

**Two refusals, back to back, and both are guards.** A pinned workspace answers
`protected: Pinned workspaces can't be closed while pinned` — cmux will not let you close your
home by accident. Then `git worktree remove` **refuses** because the lane left untracked files. Show the error verbatim:

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
