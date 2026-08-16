---
name: orchestration-loop
description: Keep watch over background work you dispatched — cmux lanes (codex/grok), Claude teammates, long builds — so a finished lane does not sit unnoticed. Use whenever you have spawned anything that runs on its own and you will need to know when it is done. Covers the watcher patterns that actually notify you, why the foreground poll you reach for first is blocked, and what to check each round. Not the same as `/loop`, which only the user can type.
---

# The orchestration loop

**The failure this prevents:** you dispatch three lanes, they all finish in four minutes, and you
find out twenty minutes later because the user told you. Nothing crashed. You simply had no
mechanism that would tell you, and a lane will never remind you.

## The mechanism, and why the obvious one does not work

| Approach | Result |
|---|---|
| `sleep 60 && check` in the foreground | **Blocked by the Claude Code harness.** So is chaining shorter sleeps to get around it. |
| "I'll check back later" | There is no later. Nothing re-invokes you. Your turn ends and the lanes run on. |
| Re-reading the screen every tool call | Wastes the turn on polling and still misses anything that finishes after you stop. |
| **A bounded background command that exits when the condition is met** | ✅ The host re-invokes you when it exits — **in Claude Code and grok**. codex has no such channel; see *Three hosts* below. |

### Three hosts, one mechanism, different tool names

This plugin installs into Claude Code, codex and grok. The signal (`agentLifecycle: idle` in
cmux's session store) and both scripts are identical everywhere — **only the way you run a
watcher differs**, and getting that wrong is how the loop silently becomes no loop at all.

| | Claude Code | grok | codex |
|---|---|---|---|
| Run a watcher in the background | `Bash(run_in_background: true)` | `run_terminal_command(background: true)` | no background channel |
| Told when it exits | yes — you are re-invoked | yes — a notification lands in the conversation | **no** |
| Read its output later | the harness surfaces it | `get_command_or_subagent_output(task_id)` | read the file you redirected into |
| Wait on several at once | one watcher each | `wait_commands_or_subagents(task_ids, mode=wait_any\|wait_all)` | — |
| Stream events as they happen | — | the `monitor` tool (one notification per output line) | — |
| Recurring prompt the **user** types | `/loop` | `/loop <interval> <prompt>` (60s minimum) | — |
| Delegate reading/synthesis in-host | `Agent` | `spawn_subagent` | its own multi-agent fan-out |

*(grok's tool names are from its shipped guide, `~/.grok/docs/user-guide/20-background-tasks.md`;
codex's absence is from `codex features list` — there is no background-shell or monitor feature.)*

🔴 **In codex, a backgrounded `&` watcher is worthless** — nothing re-invokes the turn, so it
exits into a void. Two things work instead, and both are foreground:

1. **Let the tool call block.** Run `lane-watch.sh <surfaces> --timeout-min N` directly. The
   turn waits, the user watches the panes anyway, and the call returns the moment the lanes end.
   *(Verified 2026-08-17: codex ran a 100-second foreground command to completion — it printed
   "Still waiting for the command to finish" and then returned the full output. Where the ceiling
   is was not measured, so size `--timeout-min` to what you are willing to lose if it is cut.)*
2. **Make `lane-status.sh --all` the first command of every turn.** It is one file read and it
   reports lanes that finished while nothing was watching — which in codex is *all* of them.

Everything below about **conditions** applies to every host unchanged. The condition rules are
about not lying to yourself; the table above is only about who wakes you up.

```bash
# Claude Code: Bash(run_in_background: true) · grok: run_terminal_command(background: true)
#   — returns immediately, notifies you on exit
# codex: run it in the foreground and let the call block until it prints
W=/path/to/worktree
n=0
until [ -f "$W/packages/functions/src/services/theThing.test.js" ] || [ $n -ge 60 ]; do
  sleep 10; n=$((n+1))
done
[ -f "$W/…" ] && echo "APPEARED after ~$((n*10))s" || echo "TIMEOUT after 600s"
```

**Always bound it.** An `until` with no counter hangs forever when the lane dies, and a watcher
that never exits is a loop that never runs. Print which branch you took — "TIMEOUT" is a result,
not a failure to report.

### Watch the END condition, and chain the next watcher

🔴 **A one-shot watcher is not a loop.** Waiting for a file to *appear* tells you the worker
**started**; it fires, you look, and then nothing is watching again — so you fall back to checking
by hand, which is the failure the watcher existed to prevent. *(Happened on 2026-08-11: the watcher
fired on file creation, both lanes then finished unnoticed, and the user had to ask.)*

Pick a condition that means **done**, and prefer the outcome over the process:

| Instead of | Watch for |
|---|---|
| the output file exists | **the test suite exits 0** — the thing you actually want |
| the process is alive | `pgrep -x codex` back down to the baseline — but see the caveat below |
| a report was sent | the report *plus* the gate passing |

```bash
GATE='npm test'   # your project's gate: pytest, go test, cargo test, bazel test …
n=0; until $GATE >/dev/null 2>&1 || [ $n -ge 60 ]; do sleep 10; n=$((n+1)); done
$GATE >/dev/null 2>&1 && echo "SUITE GREEN after ~$((n*10))s" || echo "STILL RED after $((n*10))s"
```

⚠️ **The process baseline drifts.** Other projects start and stop their own lanes, so the count can
end up *below* the baseline you recorded — it did, 6 → 8 → 5. Treat it as a hint, never as the
terminating condition. The gate passing is the signal that cannot drift.

**And when a watcher fires, open the next one before doing anything else.** The loop is a chain, not
a single call: found the file → now watch for green; green → now watch for the lane to exit; still
red → tell the lane, then watch again. Every round ends by arming the next round, or the loop
quietly stops after one iteration.

### The condition must name the deliverable, not its neighbourhood

Three watchers failed on 2026-08-12, all in the same direction — **they fired early and reported
success**. None ever failed by staying silent when the work was done. That asymmetry is the whole
problem: the cheap condition is always the broad one, and the broad one is always satisfied first.

| The condition I wrote | Why it fired early | The condition that works |
|---|---|---|
| `git status \| grep 'extensions/order-edit'` | matched a **new test file** the lane created; the actual panel was untouched | grep the file that must change: `grep 'OrderStatusBlock.jsx'` |
| "a tunnel URL is present in the source" | the **previous** tunnel was already there and always matched | record the old value first, require it to *differ* |
| "the URL was written" | three URLs were written that session; all three hosts were dead | `curl` it — require the thing to **answer** |

Three rules fall out:

- **Grep the artifact, not the directory.** A directory matches anything a worker touches.
- **Compare against the old value**, never merely test for presence. Whatever you are waiting to
  change is usually already there in its old form.
- **Prefer a condition that costs something to check** — a network call, a value comparison, a test
  run. If your condition is cheap and instant, it is probably measuring the neighbourhood.

And add an **early-exit for death**: `|| the worker is gone`. Two of these watchers kept polling a
process that had already exited, and silence is indistinguishable from still-working.
⚠️ Check death by artifact (port bound, file changing), not by `pgrep -f "<subcommand>"` — argv is
usually a binary path, so that pattern reports a healthy server as dead.

## Inside cmux, the agent tells you itself — stop inferring

Everything above is how to watch a worker that has no completion signal. **A cmux lane has
one.** cmux installs turn hooks into codex, grok and claude and maintains a session store:

```
~/.cmuxterm/<agent>-hook-sessions.json
```

Each entry is keyed by session and carries `surfaceId`, `pid`, `transcriptPath`, `updatedAt`,
and the field that ends the guessing — **`agentLifecycle`: `running` · `idle` · `needsInput` ·
`unknown`**. `idle` means **the turn ended**, written by the agent's own Stop hook. It is a
recorded fact, it costs one file read, and it is per-surface.

⚠️ **The plugin root differs per host, and CLAUDE_PLUGIN_ROOT is not an environment
variable** *(measured on real installs, 2026-08-13 and 2026-08-16)*:

- Claude Code **substitutes** that placeholder when it loads a skill or command markdown
  file — including inside ordinary prose, which is why this paragraph spells the name out
  instead of writing it as a shell variable.
- It is **not an environment variable**. Type it into a Bash command yourself and the shell
  expands an unset name to nothing, so the path collapses to `/skills/…` and the script
  "does not exist".
- codex installs to `~/.codex/plugins/cache/<marketplace>/cmux-workflow/<version>/` and grok to
  `~/.grok/installed-plugins/<hash>/` — **grok's path does not contain the plugin name**, so a
  name glob finds nothing there.

So resolve it by searching for a file that must exist, never by guessing a path shape:

```bash
ROOT="${CMUX_WORKFLOW_ROOT:-${CLAUDE_PLUGIN_ROOT:-${GROK_PLUGIN_ROOT:-}}}"
if [ ! -f "$ROOT/skills/cmux-orchestration/lane-status.sh" ]; then
  ROOT="$(for b in "$HOME"/.claude/plugins "$HOME"/.codex/plugins "$HOME"/.grok/installed-plugins; do
            find "$b" -maxdepth 7 -path '*skills/cmux-orchestration/lane-status.sh' 2>/dev/null | sort -V | tail -1
          done | head -1)"
  ROOT="${ROOT%/skills/cmux-orchestration/lane-status.sh}"
fi
```

```bash
# both scripts live in the cmux-orchestration skill
"$ROOT"/skills/cmux-orchestration/lane-status.sh --all                      # one-shot: which lanes are RUNNING / DONE / BLOCKED / DEAD
"$ROOT"/skills/cmux-orchestration/lane-watch.sh 440 442 --timeout-min 60    # background in Claude Code / grok, foreground in codex — exits when they end
```

⚠️ **Compare `updatedAt` against a baseline, never test `idle` for presence.** The store
already holds `idle` from previous turns, so a presence test fires instantly on stale state —
exactly the "compare against the old value" rule above. `lane-watch.sh` stamps the baseline at
arm time.

⚠️ **`running` plus a dead pid is a crash, not work.** Nothing ever writes `idle` for a killed
process, so that entry reads RUNNING forever. Check the pid or a dead lane is invisible until
your timeout.

Three cheaper-looking signals were measured on 2026-08-13 and are all wrong:

| Signal | Why it lies |
|---|---|
| `pgrep -x codex` | counts every codex on the machine — the baseline drifted 6 → 8 → 5 as other projects opened lanes |
| processes under `surface:N` in `cmux top` | **codex does not attach there.** It hangs off a workspace-level `tag:codex.<session>` bucket, so three lanes visibly mid-turn showed nothing but `zsh`/`bash` |
| `cmux events --name agent.hook.Stop` | correct, but it is a **live stream** — `--limit N` blocks until N events arrive, so every call needs a timeout wrapper. The store answers offline |

## What to wait on, per worker

| Worker | Signal that it finished | Signal it *stopped* |
|---|---|---|
| **codex lane** | `agentLifecycle: idle` newer than baseline | `running` + dead pid ⇒ crashed mid-turn |
| **grok lane** | same | same |
| **claude lane** | same — but it ends a turn as `needsInput`, not `idle` | same |
| **in-host subagent** (`Agent` · `spawn_subagent`) | its report arrives as a message | **idle notification with no report** — see below |
| **background build** | Claude Code / grok notify on exit; in codex, read the output file yourself | non-zero exit |

Pick the cheapest signal that cannot lie. A file on disk cannot lie. A screen that says "Done"
can be a summary of a failure.

### If you never armed a watcher

That is recoverable, and it is not a reason to start guessing. Run `lane-status.sh` — it
reconstructs the state of every lane from the store after the fact, including lanes that
finished while nothing was watching, and prints what still needs verifying, committing or
closing. The user-typed entry point is **`/cmux-workflow:lanes`** (plugin commands and skills
carry the plugin name as a prefix).

Do this **before** re-reading screens or counting processes. It is one command and it is the
only source that can say *finished* rather than *alive*.

⚠️ **Record the baseline before you dispatch**, or the count proves nothing:

```bash
echo "baseline: $(pgrep -x codex | wc -l)"   # BEFORE
# … dispatch …
echo "after:    $(pgrep -x codex | wc -l)"   # must be baseline+1
```

Counting after the fact and finding "5" tells you only that five codex processes exist somewhere
on the machine, most of them another project's.

## When several lanes run at once

One watcher per lane is simplest and each notifies independently. When you would rather be woken
once, wait on the slowest condition — but then a lane that dies early is invisible until the
timeout, so prefer one watcher each unless the lanes are genuinely a single unit of work.

Do **not** open a watcher per lane and *also* re-read every screen each turn. Pick one.

## Each round, five things

1. `git status --porcelain` — what changed, and **did anything outside the `owns` list change**
2. `cmux read-screen` on each lane — a live process is not a working lane; a summary is not a result
3. **Run the gate yourself** — your project's test command; read the output, compare the count to before
4. Check one specific claim from the report against the code
5. Commit what is verified. Lanes cannot commit; work sitting uncommitted is work at risk

## Idle is not done

A teammate that goes idle **without sending a report has not finished** — its final text is the
only thing that reaches you, and it sent none.

But **idle is not dead.** `idleReason: "available"` means the agent ended its turn; the process and
its whole context are still there, and one more message resumes it exactly where it stopped
(`SendMessage` in Claude Code, a follow-up to the subagent in grok, `cmux send` into the pane for a
lane). Weigh the two costs honestly:

| | Cost |
|---|---|
| Another nudge | one message |
| Dropping it | everything it read and synthesised, gone |

**So do not drop on a count, and do not stop on a hunch.** The terminating condition is **a
response** — an answer, or the agent saying explicitly that it cannot answer. Not a count of
nudges, and not "this feels like it's costing too much"; that judgement always fires early and
always loses an area.

**Degrade the ask each time until it is small enough that no live agent could fail it:**

1. **First** — "send what you have, mark gaps as could not verify", plus a priority order so it
   knows what to cut.
2. **Second** — hand it **what you have since learned** so it doesn't re-derive it, and narrow to
   the two or three questions only it can answer. An idle agent has usually spent most of its
   budget; a bare "please report" makes it decide what to cut, while a narrowed ask turns the
   remainder into one small question.
3. **Third and beyond — change the *shape* of the question, not just its size.** Ask for one
   sentence. Ask it to paste a URL. Ask a yes/no. "Can a non-Plus dev store render this extension —
   yes or no, plus the link?" is answerable in one line by an agent with almost nothing left.
4. **Cover the area yourself in parallel** — but in parallel, not instead. Keep the agent alive; a
   later answer still improves the plan, and merging it in costs a paragraph.

Whatever happens, **say in your summary which areas came back thin and which you covered by hand**,
so nobody reads the plan and assumes that research happened.

*(2026-08-11: of five research agents, three reported only after a nudge and two went silent twice.
An earlier version of this skill said "drop after the second idle". Following it cost an entire
research area — three of seven questions were then answered by hand, worse, including the one
plan-gating question that had killed a previous plan outright. The rule was wrong: dropping trades
a whole area for the price of one message.)*

## `/loop` is not this

`/loop` is a **built-in that the user types** — in Claude Code (self-paced via `ScheduleWakeup`)
and in grok (`/loop <interval> <prompt>`, 60s minimum, each firing a new turn). codex has no
equivalent. **You cannot invoke it in any of them**, and in Claude Code a project command of the
same name is silently shadowed — do not create `.claude/commands/loop.md`.

So: if the user has started `/loop`, each firing is your round above. If they have not, **the
watcher is your only mechanism** — an instruction to "start the loop" that you cannot execute is
the same as no loop at all, which is exactly how three lanes finished unnoticed.

## Related

- `cmux-orchestration` (global skill) — opening lanes, the five dispatch steps, briefs
- `agent-teams` — Claude teammates and their limits (a separate skill, Claude Code only, not
  bundled here). Under grok the equivalent is `spawn_subagent`; codex has its own fan-out.
- `.claude/commands/new-feature.md` — Phase 3 dispatch, Phase 4 verification
