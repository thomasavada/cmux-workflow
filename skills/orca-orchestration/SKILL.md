---
name: orca-orchestration
description: Dispatch and watch parallel coding-agent lanes as Orca terminals, and know the moment each finishes. Use when the host is Orca (the user says "orca", "$orca-cli", "split in orca", "spawn codex in a worktree" and Orca is running), when lanes may already be running in Orca ("are the lanes done", "close the finished lanes"), or when you are about to implement several disjoint slices yourself one by one. The WHEN-to-lane and how-to-brief rules live in cmux-orchestration and are not repeated here — this skill owns only what Orca genuinely does differently: terminal creation, the probe, and a completion signal that does not lie.
---

# Orca lanes

## 0 · Read the shared discipline first, it is not repeated here

Everything about **when** to open a lane, how to slice `owns`, how to write a brief
that survives, worktree setup and teardown, and why a live process is not a working
lane — lives in **`cmux-orchestration/SKILL.md`**, in this same plugin:

```
${CLAUDE_PLUGIN_ROOT}/skills/cmux-orchestration/SKILL.md
```

Read it. This file deliberately does not restate it: two copies of one discipline
drift, and the drifted copy is the one someone follows.

What is genuinely different in Orca is small, and all of it is below.

## 1 · The one real difference: Orca cannot tell you a lane is idle

cmux exposes `agentLifecycle == "idle"` from its own turn-hook session store — a
recorded fact, so `lane-watch.sh` cannot be fooled. **Orca has no such store, and its
nearest equivalent lies:**

| Signal | Verdict |
|---|---|
| `orca terminal wait --for tui-idle` | 🔴 **reports idle mid-turn.** Four false "settled" reports in one session |
| `pgrep -x codex` count | 🔴 a live process is not a working lane (§5 of the shared skill) |
| `Worked for 27m 57s` footer | 🔴 **only printed for long turns.** See below |
| **"esc to interrupt" on the live screen** | ✅ busy — covers `Working (3s …)` and `Waiting for background terminal (1m 05s …)` |
| **"Ask Codex to do anything" with no busy marker** | ✅ idle |

🔴 **The footer is the trap, because it looks like the right answer.** Long lanes
end with `─ Worked for 27m 57s ─`, so a footer-based watcher tests beautifully
against them — and then hangs forever on the lanes that finish fastest, which print
no footer at all. A measured one-shot turn ends like this, complete, with nothing
to match:

```
• READY
› Ask Codex to do anything
```

This was found by running the watcher against a real lane *after* writing it the
wrong way. Read state off the input box instead; it is always rendered.

So watch for the busy→idle transition, never for a lane to look quiet:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/orca-orchestration/orca-lane-watch.sh \
  --handles term_aaa,term_bbb        # or --auto for this worktree's codex lanes
```

🔴 **Arm it in the same turn you dispatch.** Not after the next message, not "once I've
checked on them". A terminal parked at its prompt is *idle* by this test, so the watcher
refuses to call a lane finished until it has seen it busy at least once (with
`lastOutputAt` advancing past arm time as the tiebreaker for a lane that finishes
between two polls). Arm it late and you lose that transition.

Measured on a real lane — the whole point is that middle line:

```
armed term_249c19a5… (state=idle)
round 1 (1s):  term_249c19a5-=idle      ← dispatch has not landed yet
round 2 (7s):  term_249c19a5-=busy      ← seen busy, now it may finish
round 3 (13s): term_249c19a5-=done
ALL LANES FINISHED
```

To audit lanes you did not watch: `orca-lane-status.sh` (`--all` for every worktree).

## 2 · Dispatch — the five steps, with Orca mechanics

Same five steps as the shared skill. Only the commands differ.

```bash
# 0 · baseline BEFORE dispatch, or step 4's count proves nothing
pgrep -x codex | wc -l

# 1 · brief to a tracked FILE, never stuffed into the send string
#     docs/plans/briefs/<ID>.md

# 2 · create the terminal — then LIST to get its handle
orca terminal create --command "cd $PWD && exec \$SHELL -l" --json
orca terminal list --json     # ← the handle is here, not usefully in create's output
orca terminal rename --terminal <handle> --title "Lane <ID>"

# 3 · PROBE — make the shell prove it reads keystrokes, inside the repo
orca terminal send --terminal <handle> --text "touch .lanes/tmp/probe-<ID>" --enter
ls .lanes/tmp/probe-<ID>      # MUST appear. If not: close the terminal, recreate.

# 4 · dispatch: ONE sentence pointing at the brief, model and effort pinned
orca terminal send --terminal <handle> --enter --text \
  'codex -s workspace-write -a never --strict-config -m gpt-5.6-sol \
   -c model_reasoning_effort=xhigh -c sandbox_workspace_write.network_access=true \
   "Lane <ID>. Read docs/plans/briefs/<ID>.md and follow it."'
pgrep -x codex | wc -l        # MUST be baseline+1

# 5 · READ THE SCREEN, then arm the watcher in this same turn
orca terminal read --terminal <handle> --screen --limit 15
```

## 3 · Flag reality — every one of these was a real failure

The Orca CLI does not forgive guessed flags, and several near-misses are plausible
enough to type by accident:

| Typed | Reality |
|---|---|
| `orca terminal send-text` | ✗ **no such command.** It is `send` |
| `orca terminal read --lines 30` | ✗ it is `--limit`. (The CLI does suggest this one) |
| `orca terminal read` without `--screen` | returns buffered output, not the visible pane |
| `orca terminal create --json` → handle | the handle is **not** usefully in the output; `terminal list` after |
| `orca terminal send --terminal ""` | 🔴 **does not error — it picks a terminal.** See below |
| bare `orca` on Linux | 🔴 that is the **GNOME screen reader** — starts speech. Use `orca-ide` or `ORCA_CLI_COMMAND` |

🔴 **An empty or unset `--terminal` silently sends to some other pane.** A handle
extracted by a script that returned nothing produced
`Sent 40 bytes to term_59d0a155…` — a *different* terminal, running a Claude
session, which received the command as chat input. It reports success. Assert your
handle is non-empty before every send; a typo here types into someone else's agent.

🔴 **Once the lane's TUI is up, `send` talks to the agent, not the shell.** You
cannot re-dispatch by sending another `codex …` command line — it goes into the
prompt box as a message. To get back to a shell, `send --interrupt` first.

**Reasoning effort: `minimal` is rejected.** `-c model_reasoning_effort=minimal`
returns HTTP 400 from the API (`Unsupported value … Supported values are: 'none',
'low', 'medium', 'high', 'xhigh', and 'max'`) on `gpt-5.6-sol`. The shared skill's
ladder lists `minimal` and warns that bad values are swallowed silently; neither
holds here — it fails loudly, and the lane sits at an error with no turn to watch.

🔴 **Never `2>/dev/null` an Orca command.** `send-text` failed silently behind a
redirect for a full round: the probe file never appeared, and the obvious reading was
"the shell is dead" rather than "the subcommand does not exist". Both scripts here
deliberately leave stderr alone.

Version-matched truth for anything not listed: `orca skills get orca-cli`.

## 4 · Titles do not stay where you put them

`orca terminal rename --title "Lane S1"` works, and then **Orca overwrites it with the
agent identity** (`codex`) once the agent starts. Track lanes by handle; treat the
title as a hint for the human, not an identifier for you.

## 5 · Closing a lane

A codex lane in a sandbox **cannot commit** — its work is sitting in the working tree
by design. Closing the pane discards anything uncommitted, and `git status` is the
only thing standing between you and losing a 27-minute turn.

```bash
git status --porcelain          # MUST be harvested first
orca terminal close --terminal <handle> --tab
```

Verify the drop afterwards: `pgrep -x codex | wc -l` should fall by exactly the number
you closed. If it does not, you closed a tab and left the agent running.
