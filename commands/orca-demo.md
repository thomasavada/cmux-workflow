---
description: Live guided demo of parallel lanes in Orca — two agents, a watcher that cannot lie, and the four traps that each cost a real session
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Skill
---

One walkthrough that proves **parallel lanes in Orca**. You will create terminals, probe them,
dispatch two agents, arm a watcher, watch it settle on the busy→idle transition, and tear it all
down. Narrate as you go: the point is that the audience understands the mechanism, not that they
saw some panes.

This is **not** the cmux demo with different commands. Orca's hard part is somewhere else, and
the demo is built around that difference.

## The one question the whole demo answers

> **"The lane is running. How do I know the moment it stops — without staring at it?"**

Say it out loud at the start and answer it at the end. In cmux that question is nearly free:
cmux records `agentLifecycle: idle` in its own turn-hook store, so a watcher reads a fact.
**Orca publishes no such fact.** Everything below is the consequence.

## 🔴 The trap that makes this demo worth running

Orca offers something that looks like the answer and is not:

```bash
orca terminal wait --for tui-idle      # ← reports idle MID-TURN. Do not build on it.
```

Four false "settled" reports in one session. The audience must see this named, or they will
reach for it the same afternoon.

The replacement people reach for second is worse, because it *tests clean*. Codex ends long
turns with `─ Worked for 27m 57s ─`, so a footer-based watcher passes every trial against slow
lanes — then hangs forever on a fast one, which prints no footer at all:

```
• READY
› Ask Codex to do anything          ← a complete turn. No footer anywhere.
```

Show both. A demo that only shows the working path teaches nothing about why it is built this way.

## Load the skills first — this file does not restate them

| Skill | What it owns |
|---|---|
| `cmux-workflow:cmux-orchestration` | **when** to lane, how to slice `owns`, how to write a brief, teardown. Host-agnostic — read it |
| `cmux-workflow:orca-orchestration` | the Orca mechanics: terminal creation, the probe, flag traps, the completion signal |

One rule, one home. If you find yourself explaining *when* to open a lane, you are in the wrong
file — that is `cmux-orchestration` §1.

## Before you start — ask

This spends tokens and opens terminals. Say so, get a yes, then check:

```bash
command -v codex || echo "missing codex"
orca status --json >/dev/null && echo "orca runtime reachable"   # `orca open --json` if not
git rev-parse --show-toplevel
mkdir -p .lanes/tmp                       # probe target; must be gitignored
orca terminal list --json > /tmp/orca-demo-before.json   # the diff target for teardown
```

⚠️ On Linux a bare `orca` is the **GNOME screen reader** and will start speech on the presenter's
machine. Use `orca-ide`, or set `ORCA_CLI_COMMAND`. Check this before the room is watching.

## Ground rules

- **Narrate the WHY**, one or two sentences per step. Every step exists because something failed
  without it. Say which.
- **Show what refuses.** Two steps below are *supposed* to fail. Those are the lessons.
- **Touch nothing of theirs.** Close only terminals this demo created; `/tmp/orca-demo-before.json`
  is how you prove it.
- **Never `2>/dev/null` an Orca command** on stage or off. See Act 1.

---

## Act 1 · Create a terminal, then prove it is listening (90s)

Two surprises live in this one act.

```bash
orca terminal create --command "cd $PWD && exec \$SHELL -l" --json
orca terminal list --json          # ← the handle is HERE, not usefully in create's output
```

**Surprise one:** `create` does not hand you the handle. Everyone assumes it does.

Now the probe. Do not skip it and do not fold it into the dispatch:

```bash
H=term_...                                    # from the list above
orca terminal send --terminal "$H" --text "touch .lanes/tmp/probe-DEMO" --enter
ls .lanes/tmp/probe-DEMO                      # MUST appear
```

**Surprise two — do this live, it lands better than any slide.** Type the plausible-looking
wrong command:

```bash
orca terminal send-text --terminal "$H" --text "..."     # ✗ no such command; it is `send`
orca terminal read --terminal "$H" --lines 30            # ✗ it is `--limit`
```

Then explain what makes it dangerous rather than annoying: in a real session both of these were
run with `2>/dev/null` attached, so they failed **silently**, the probe file never appeared, and
the obvious reading was "the shell is dead" rather than "the subcommand does not exist".

🔴 **And the worst one.** If `$H` is empty — a script that returned nothing, a typo — the send
does **not** error:

```
Sent 40 bytes to term_59d0a155-…        ← a DIFFERENT terminal
```

In the session this came from, that terminal was running a Claude agent, which received a shell
command as chat input. Assert the handle is non-empty before every send.

## Act 2 · Two lanes, disjoint files, briefs on disk (2 min)

Briefs go in files, never stuffed into the send string — `cmux-orchestration` §1.2 says why.
Write two throwaway briefs whose `owns` genuinely cannot overlap, then:

```bash
pgrep -x codex | wc -l                 # BASELINE first, or the check after proves nothing

orca terminal send --terminal "$H" --enter --text \
  'codex -s workspace-write -a never --strict-config -m gpt-5.6-sol \
   -c model_reasoning_effort=xhigh -c sandbox_workspace_write.network_access=true \
   "Lane D1. Read docs/plans/briefs/D1.md and follow it."'

pgrep -x codex | wc -l                 # MUST be baseline+1
```

**Show the effort trap** — it is one line and it saves someone an afternoon:

```bash
-c model_reasoning_effort=minimal      # → HTTP 400
# Unsupported value: 'minimal' … Supported values are:
#   'none', 'low', 'medium', 'high', 'xhigh', and 'max'
```

The lane comes up, errors, and sits there. No turn ever starts, so there is nothing for a
watcher to settle on — which is exactly the failure the next act is about.

⚠️ **Once the TUI is up, `send` talks to the agent, not the shell.** You cannot re-dispatch by
sending another `codex …` line; it goes into the prompt box as a message. `send --interrupt`
first to get a shell back.

## Act 3 · 🎯 Arm the watcher in the same turn — the whole point (2 min)

This is the act. Everything before it was setup.

```bash
ROOT="$(for b in "$HOME"/.claude/plugins "$HOME"/.codex/plugins "$HOME"/.grok/installed-plugins; do
          find "$b" -maxdepth 7 -path '*skills/orca-orchestration/orca-lane-watch.sh' 2>/dev/null |
          sort -V | tail -1
        done | head -1)"
ROOT="${ROOT%/skills/orca-orchestration/orca-lane-watch.sh}"

bash "$ROOT/skills/orca-orchestration/orca-lane-watch.sh" \
  --handles "$H1,$H2" --interval 10        # background it in Claude Code / grok
```

Say why *same turn* is not pedantry: a terminal parked at its prompt is **idle** by this test, so
the watcher refuses to call a lane done until it has seen it **busy** at least once. Arm it late
and you have thrown that transition away.

Read the log out loud when it settles — the middle line is the lesson:

```
armed term_249c19a5… (state=idle)
round 1 (1s):  =idle      ← dispatch has not landed yet
round 2 (7s):  =busy      ← seen busy; only now may it finish
round 3 (13s): =done
ALL LANES FINISHED
```

Thirteen seconds, on a turn that printed **no `Worked for` footer at all**. A footer-based
watcher would still be polling.

## Act 4 · Ask the question the demo opened with (60s)

```bash
bash "$ROOT/skills/orca-orchestration/orca-lane-status.sh"
```

Then immediately undercut it, because the honest limit is part of the lesson:

> `idle` means *not working right now*. It does **not** mean the brief is done — a lane that
> stopped to ask you a question is idle too. Read the screen before you believe it.

That distinction is why `lane-status` and `lane-watch` are separate tools: the watcher has an
arm-time baseline and can talk about *this* turn; the status read is a point-in-time glance.

## Act 5 · Verify by artifact, not by report (60s)

A lane's own summary is a claim. Check the tree:

```bash
git status --porcelain
git diff --stat
```

🔴 **A codex lane cannot commit** — the sandbox cannot write `.git/index.lock`. So everything it
produced is sitting uncommitted, and closing the pane discards it. Say this before teardown, not
during.

## Act 6 · Teardown, and let it refuse (90s)

```bash
git status --porcelain                     # harvest FIRST — this is the guard, not a formality
orca terminal close --terminal "$H1" --tab
orca terminal close --terminal "$H2" --tab
pgrep -x codex | wc -l                     # MUST fall by exactly 2
```

If the count does not drop, you closed a tab and left the agent running — say so out loud rather
than moving on; that is the failure mode this check exists for.

**One last Orca-ism to show:** `orca terminal rename --title "Lane D1"` works, and then Orca
overwrites it with the agent identity (`codex`) the moment the agent starts. Titles are a hint
for the human. Track lanes by handle.

## Verify nothing was left behind

```bash
orca terminal list --json > /tmp/orca-demo-after.json
python3 - <<'PY'
import json
b = {t["handle"] for t in json.load(open("/tmp/orca-demo-before.json"))["result"]["terminals"]}
a = {t["handle"] for t in json.load(open("/tmp/orca-demo-after.json"))["result"]["terminals"]}
print("leaked terminals:", a - b or "none")
PY
rm -f .lanes/tmp/probe-DEMO
```

`leaked terminals: none`, and the codex count back to baseline. Then answer the opening question
in one sentence: *the watcher told me, and it could not have told me wrong, because it had to see
the lane busy before it was allowed to say done.*

## Timing, and what to cut

Full run ≈ 10 min. If you have 5: keep **Act 1's three traps** and **Act 3**, cut Acts 2 and 5 to
a sentence each. Do not cut Act 6 — a demo that leaves terminals open teaches the opposite of
the point.

## Deliberately out of scope

Worktrees, groups and screen layout. Those are `cmux-orchestration` §1.1 and
`cmux-screen-layout`, and they are host-agnostic enough that duplicating them here would create
the second copy that drifts.
