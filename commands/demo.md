---
description: Live guided demo of cmux + parallel lanes — sidebar, groups, status lanes, four agents at once, then tear it all down
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill
---

One walkthrough that teaches **cmux** and then proves **parallel lanes** on top of it. You will
actually create a group, a worktree, a workspace, four agent panes and a watcher — then remove
every trace. Narrate as you go: the point is that the audience understands the mechanism.

## The one question the whole demo answers

> **"I have eight things running. Which one needs me right now?"**

Say it out loud at the start and answer it at the end. Every step below is an answer to it. Do
not present a feature list — a list teaches nothing and is forgotten by the lift.

## 🔴 "Lane" means two things — settle it in the first minute

| Say | What it is | Where it lives |
|---|---|---|
| **status lane** | cmux's own idea: `todo · working · needs-attention · review · done` | the sidebar row |
| **agent pane** | a split running codex/claude/grok | inside a workspace |

An audience that hears one word mean two things stops following and never tells you.

## Load the skills first — this file does not restate them

| Skill | What it owns |
|---|---|
| `cmux-workflow:cmux-screen-layout` | **where the panes go.** Read it BEFORE the second pane |
| `cmux-workflow:cmux-orchestration` | §1.1 worktree+group · §5.0 dispatch · §2 briefs · §1.1a teardown |
| `cmux-workflow:orchestration-loop` | why a background watcher is the only thing that notifies you |

🔴 **Skipping the layout skill is how this demo failed its first real run** *(2026-08-13)*: four
`new-split right` in a row produced five ~40-column panes with codex's box drawing wrapped into
soup. The lanes were all working. Nobody could read them. **A demo nobody can read is a failed
demo.** If the panes come out unreadable, stop and fix the layout before dispatching anything.

## Before you start — ask

This spends tokens, opens panes, and writes a throwaway branch. Say so, get a yes, then check:

```bash
command -v cmux codex || echo "missing a prerequisite"
ls ~/.cmuxterm/*-hook-sessions.json >/dev/null 2>&1 || echo "run: cmux hooks setup"
git rev-parse --show-toplevel
cmux workspace list > /tmp/demo-before.txt      # the diff target for the last step
```

⚠️ **Claude lanes bill against the same weekly quota as the chat driving them** — the Claude TUI
footer prints the percentage used. codex bills separately. If the budget is tight, run the
**two-lane cut** (`hello` + `review`); every lesson survives.

## Ground rules

- **Narrate the WHY**, one or two sentences per step. Every step exists because something failed
  without it; say which.
- **Show what refuses.** Two commands in teardown are *supposed* to fail. Those are the lessons.
- **Touch nothing of theirs.** Everything lives in a throwaway group; only ever close what this
  demo created.
- If a step fails, **stop and explain** rather than pushing on — then still run teardown.

---

## Act 1 · The sidebar is a queue, not a file tree (90s)

Show their real sidebar. Ask *"which of these is finished?"* and let the silence sit — the honest
answer is that you have to click into each one.

Then build somewhere to work, **inside its own group**, so nothing lands on top of their pinned
projects:

```bash
G=$(cmux workspace-group create --name "demo" | grep -o 'workspace_group:[0-9]*')
cmux workspace create --name "cmux-demo" --cwd "$WT" --group "$G" --focus false
cmux workspace-action --action pin       --workspace <ref>
cmux workspace-action --action set-color --workspace <ref> --color "#4C8DFF"
```

*The lesson:* the rail is ordered by **importance, not history** — pinned rows form their own
group at the top. ⚠️ Creating a group also creates an **anchor** workspace to own it, so expect
one more row than you made.

Say that real lane work **inherits the caller's group** instead of making its own; a demo gets its
own only because it is disposable as a unit. The resolver is in `cmux-orchestration` §1.1.

## Act 2 · A worktree, outside the repo tree (60s)

```bash
REPO="$(git rev-parse --show-toplevel)"
WT="$HOME/cmux/worktrees/$(basename "$REPO")/demo-$(date +%H%M%S)"
mkdir -p "$(dirname "$WT")"; git worktree add "$WT" -b chore/cmux-demo
```

*Why outside:* nested worktrees make every scan-the-whole-tree tool find the same config several
times; one CLI refused to start over exactly that. Say that a real worktree needs the project's
setup step — gitignored config, `node_modules`, build output — and that this demo skips it
because the lanes write one file each.

## Act 3 · Four lanes, four different jobs (2–3 min)

One lane proves the plumbing. **Four show what it is for**, and they finish at different times.

| Lane | Agent | Why it is here |
|---|---|---|
| `DEMO-1 hello` | codex `low` | fastest possible lane — the first `DONE` lands while you are still talking |
| `DEMO-2 review` | **claude `--model sonnet`** | a lane is not "a codex thing" — and it need not be the family you are driving from; the big model orchestrates, a cheaper one works |
| `DEMO-3 security` | codex `xhigh`, read-only | effort chosen by **blast radius**, not by how hard it feels |
| `DEMO-4 implement` | codex in the **worktree** | the only one that writes code — and it cannot commit |

Best demo material is a repo with **planted defects**, so the audience can check findings against
something known. `~/cmux/demo-sandbox`, if present, has an off-by-one, a SQL injection and a
hardcoded key; the lanes found all three with line numbers on 2026-08-13.

Write each brief to a file — never into the `send` string, which types through a simulated
keyboard. Dispatch, taking the split direction from the **layout skill**, not from here:

```bash
cmux new-split <direction per the layout skill> --workspace workspace:<W>
cmux rename-tab --workspace workspace:<W> --surface surface:<N> "DEMO-2 review"
sleep 4                                    # let the shell finish starting — see Act 4
cmux send     --workspace workspace:<W> --surface surface:<N> "<agent command>"
cmux send-key --workspace workspace:<W> --surface surface:<N> Enter
```

The two agent lines, and the flag that matters in each:

```bash
# codex — -a never is what stops it halting on an approval nobody is watching
codex -s workspace-write -a never --strict-config -m gpt-5.6-sol -c model_reasoning_effort=low "Lane DEMO-1. Read BRIEF-1.md and follow it."

# claude — acceptEdits is NOT the equivalent: it auto-accepts EDITS and still stops at every Bash
# command. Measured 2026-08-13: the lane sat on "Do you want to proceed?" looking like it was busy.
claude --model sonnet --permission-mode bypassPermissions "Lane DEMO-2. Read BRIEF-2.md and follow it."
```

🔴 **Say that codex/Claude difference out loud.** It is the most useful thing in this section and
it is invisible until a lane hangs.

⚠️ **Carry `--workspace` on every call aimed at another workspace's surface** — rename, send,
send-key, read-screen — or you get `not_found: Tab not found`.

## Act 4 · Read every screen (60s)

```bash
cmux read-screen --workspace workspace:<W> --surface surface:<N> --lines 20
```

*Why:* **a live process is not a working lane.** In a fresh directory every lane stops on
`Do you trust the contents of this directory?`, which `-a never` does not suppress — send `Enter`.
A lane stuck there reports **EMPTY** in `lane-status`, not RUNNING, because no session has opened
yet. That is the tell.

⚠️ **Give the shell ~4s before probing or dispatching.** A probe checked 2s after `new-split`
reported failure while the screen showed the command *had* run — the shell was still printing
`Last login`. "Probe failed ⇒ recreate the pane" would have thrown away a healthy pane.

## Act 5 · 🎯 The machine tells you — the whole point (2–3 min)

Everything so far was tidying. This is why cmux exists.

```bash
cmux workspace status --workspace <ref>          # effective / inferred / override
```

**Nobody set that.** cmux watched the agents and inferred it; the lane moves through
`todo → working → needs-attention → review → done` on its own.

> *"I never told it anything. It is watching the agents, and the rail is telling me where to look."*

Deliver that **facing away from the panes**, pointing at the sidebar. It is the one line they will
repeat to someone else.

⚠️ Do **not** script an agent to set the status — cmux's CLI contract reserves the checklist and
manual pins for the user, precisely because the lane is already inferred. Show the command
(`cmux workspace status set …`), say it is theirs, and move on. A freshly created empty workspace
already infers `working`, not `todo` — don't promise a state they will not see.

Then the tooling on top of it:

```bash
lane-status.sh --all                          # RUNNING / DONE / BLOCKED / DEAD / EMPTY, per lane
lane-watch.sh <N> <N> <N> --timeout-min 8     # background it in Claude Code / grok; foreground in codex
```

`lane-status` reads `agentLifecycle` from cmux's own store — a fact written by each agent's Stop
hook, not a `pgrep` guess. Show the `⚠ no watcher` flags, then arm one and show them disappear.
*Why background:* Claude Code and grok re-invoke you when a background command **exits**; that is
the only mechanism that will ever tell you a lane finished. If you are demoing from codex, say
that it has no such channel and run the watcher in the foreground — the wait is the demo. Three lanes, one watcher, all three fired
`DONE` at ~20s on 2026-08-13.

⚠️ codex and Claude **end a turn differently** — codex goes `idle`, Claude goes `needsInput`
because its TUI is back at an empty prompt. `lane-status` already separates "finished" from
"actually blocked"; mention it so nobody trusts a raw lifecycle field.

## Act 6 · Verify by artifact, not by report (60s)

```bash
cat review.md security.md                     # what the lanes actually produced
git -C "$WT" status --porcelain               # DEMO-4's work — UNCOMMITTED by design
git -C "$WT" log --oneline -1                 # unchanged: a worktree lane cannot commit
```

A lane reporting "done" is not evidence. And a worktree lane's output exists **only** in the
working tree: `.git` is a file pointing at the main repo, whose object store sits outside the
sandbox's writable root.

## Act 7 · Teardown — and let it refuse twice (90s)

```bash
cmux workspace-action --action unpin --workspace <ref>     # Act 1 pinned it
cmux workspace-group delete "$G" --close-workspaces        # group + every member, one command
git worktree remove "$WT"                                  # EXPECT THIS TO REFUSE
```

**Two refusals, back to back, and both are guards.**

```
Error: protected: Pinned workspaces can't be closed while pinned.
fatal: '<path>' contains modified or untracked files, use --force to delete it
```

*This is the most important moment of the demo.* The second is the guard between routine cleanup
and deleting a lane's entire output — and a worktree is where that hurts most, because nothing was
committed. Harvest first, then remove:

```bash
cat "$WT/<the lane's file>"        # this is what --force would have destroyed
git worktree remove --force "$WT"  # only now, and only because we read it first
git branch -d chore/cmux-demo      # plain -d
git worktree prune
```

⚠️ `-d` succeeds here only because the lane could not commit, so the branch never left its base
and git considers it merged. On a real feature branch it would refuse. Say so, rather than letting
them conclude `-d` is always safe. Removing a worktree never deletes its branch.

## Act 8 · Land it (30s)

Answer the opening question in one sentence:

> **"Eight things running, and the rail tells me which one needs me — because cmux is watching the
> agents, not because I remembered to check."**

Then two next steps, no more: `/cmux-workflow:lanes` for state at any time, and arming
`lane-watch.sh` at dispatch so nothing finishes unnoticed.

## Verify nothing was left behind

```bash
cmux workspace list | diff /tmp/demo-before.txt -   && echo clean
git worktree list | grep -c 'demo-'                 # 0
git branch --list 'chore/cmux-demo'                 # empty
```

## Timing, and what to cut

| Act | Target | |
|---|---|---|
| 1 · sidebar as queue | 1:30 | cut to 60s if long |
| 2 · worktree | 1:00 | **first to cut** |
| 3 · four lanes | 2:30 | cut to two lanes |
| 4 · read the screens | 1:00 | |
| 5 · **the machine tells you** | 2:30 | 🔴 **never cut** |
| 6 · verify | 1:00 | |
| 7 · teardown refusals | 1:30 | 🔴 never cut the refusals |
| 8 · land it | 0:30 | |

**~11 minutes full, ~7 with the cuts.** Act 5 and the Act 7 refusals are the only parts anyone
repeats to a colleague.

## Deliberately out of scope

SSH/remote workspaces, the browser panel, custom dock and sidebars, agent hibernation, `cmux vm`.
Each is a good second video. Here they are all the same mistake: answering a question the audience
has not asked yet.
