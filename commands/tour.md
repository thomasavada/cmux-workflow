---
description: Teach cmux itself in 6–8 minutes — the sidebar, workspaces, status lanes, panes, notifications — with throwaway workspaces that clean themselves up
allowed-tools: Bash, Read, Glob, Grep
---

A guided tour of **cmux**, for someone who has it installed and does not yet see why it beats
tabs in a terminal. Spawns no agents and spends no tokens on models, so it is safe to rehearse
and safe to run live in front of an audience.

**This is not `/cmux-workflow:demo`.** That one proves the *plugin* works by dispatching a real
codex lane. This one explains the *app*.

## The one question the whole tour answers

> **"I have eight things running. Which one needs me right now?"**

Every feature below is an answer to that. Say the question out loud at the start and return to it
at the end. Do not present a feature list — a list teaches nothing and is forgotten by the lift.

## 🔴 The word "lane" means two different things — settle it in the first minute

| Term to use | What it is | Where it lives |
|---|---|---|
| **status lane** | cmux's own idea: `todo · working · needs-attention · review · done` | the sidebar row |
| **agent pane** | a split running codex/grok — what this plugin's other docs call a "lane" | inside a workspace |

Say this once, plainly, then be consistent. An audience that hears "lane" mean two things stops
following and never tells you.

## Ground rules

- **Touch nothing of theirs.** Everything below runs on workspaces this tour creates and then
  closes. When a lesson applies to their real setup, *show them the command* and let them decide.
- **`cmux` is scriptable, but the audience is watching the UI.** Run the command, then point at
  the sidebar. The command is evidence; the sidebar is the lesson.
- Capture the starting state and diff against it at the end:

```bash
cmux list-workspaces > /tmp/tour-before.txt; wc -l < /tmp/tour-before.txt
```

---

## Act 0 · The mess (30s)

Show their real sidebar as it is. Ask: *"which of these is finished?"* Let the silence sit — the
honest answer is that you have to click into each one.

Do not fix anything yet. The rest of the tour is the fix.

## Act 1 · The sidebar is a queue, not a file tree (90s)

Create two throwaway workspaces so there is something to organise:

```bash
cmux workspace create --name "tour-main" --focus false      # new-workspace is the old alias
cmux workspace create --name "tour-scratch" --focus false
```

Then three moves, each one visible instantly in the rail:

```bash
cmux workspace-action --action pin       --workspace <ref>                      # sticks to the top
cmux workspace-action --action set-color --workspace <ref> --color "#4C8DFF"    # name or #hex
cmux workspace-action --action rename    --workspace <ref> --title "◆ main"
```

*The lesson:* the rail is **ordered by importance, not by history**. Pinned rows form their own
group at the top — `reorder-workspaces` sorts inside pinned and unpinned groups separately.

Full action set, worth naming so they know it exists: `pin · unpin · rename · clear-name ·
set-description · clear-description · set-color · clear-color · move-up · move-down · move-top ·
close-others · close-above · close-below · mark-read · mark-unread`.

**Hand them the takeaway command for their own setup** — do not run it yourself:

> *"Pin your main workspace and give it a colour. One command, and you stop hunting for home."*

## Act 2 · One piece of work = one workspace (60s)

```bash
cmux workspace create --name "tour-feature" --cwd "$HOME" --focus false
```

*The lesson:* a workspace carries its **own working directory**, and optionally its own
environment (`--env KEY=VALUE`, `--env-file`). That is why a feature gets a workspace rather than
a tab: the context travels with it. Mention that a git worktree slots in here as `--cwd` — and
that it is a `git` topic, deliberately out of scope for this tour.

## Act 3 · Parallel work lives in panes (60s)

```bash
cmux new-split right --workspace <tour-feature ref>          # → prints its own surface ref
cmux rename-tab --workspace <ref> --surface surface:<N> "build"
```

🔴 **Carry `--workspace` on every call aimed at another workspace's surface** — rename, send,
send-key, read-screen. Without it you get `not_found: Tab not found`, because `--surface`
resolves inside the caller's workspace.

*The lesson, said out loud:* **workspace = what you are working on; pane = who is working on it.**
Also mention `tab-action --action new-terminal-right` as the "spawn one to the right" they will
reach for, and that panes get named immediately because surface refs are renumbered as panes come
and go.

## Act 4 · 🎯 The status lane — the whole point (2–3 min)

Everything so far is tidying. This is why cmux exists.

```bash
cmux workspace status --workspace <ref>
```

It prints three lines — **effective**, **inferred**, **override**. Read them aloud:

```
needs-attention
inferred: needs-attention
override: none (auto)
```

⚠️ A **freshly created, empty** workspace already infers `working`, not `todo` *(measured
2026-08-13)*. Don't promise the audience a `todo` they will not see. The contrast worth pointing
at is between a workspace with a live agent and one that has gone quiet.

**Nobody set that.** cmux watched the agent in that workspace and inferred it. The lane moves
through `todo → working → needs-attention → review → done` on its own.

> *"I never told it anything. It is watching the agents, and the rail is telling me where to look."*

That sentence is the tour. Deliver it while **facing away from the panes**, pointing at the
sidebar.

⚠️ **Do not script an agent to set the status** — and say why on camera, because the honesty
lands well. cmux's own CLI contract states it plainly:

> *"the checklist and manual status pins belong to the user. Coding agents must not … set/cycle
> the status … The status lane already tracks agent activity automatically through inference."*

A manual pin exists for humans — `cmux workspace status set <todo|working|needs-attention|review|
done|auto>` — and it **auto-clears once the inferred lane changes**. Show the command, explain it
is theirs to use, and move on without running it on their real workspaces.

Then the three things that reach across the screen:

```bash
cmux notify --workspace <ref> --title "Build finished" --subtitle "tour" --body "3 tests added"
cmux trigger-flash --workspace <ref>          # flashes the row — cheap, and it reads on camera
cmux right-sidebar feed                        # the Feed: agent events as they happen
```

**Optional, only if the room is engaged** — the checklist. Ask first; per the same policy it
belongs to the user:

```bash
cmux todo add "wire the endpoint" --origin agent --workspace <ref>
cmux todo start 1 --workspace <ref>            # in-progress shows on the sidebar row
cmux todo list --workspace <ref>
```

## Act 5 · Closing the loop (60s)

Two commands, and the tour has told a complete story:

```bash
cmux diff --last-turn --cwd <a repo>           # exactly what the agent changed last turn
cmux markdown open <some plan>.md              # the plan, rendered, live-reloading beside the work
```

*The lesson:* you review from the same screen you dispatched from. Nothing to alt-tab to.

Then close what the tour made:

```bash
cmux workspace-action --action unpin --workspace <ref>   # REQUIRED if you pinned it in Act 1
cmux close-workspace --workspace <ref>
```

🔴 **A pinned workspace refuses to close** *(measured 2026-08-13)*:

```
Error: protected: Pinned workspaces can't be closed while pinned. Unpin the workspace first.
```

Pinning in Act 1 and closing in Act 5 is exactly the sequence this tour walks, so unpin first or
the last minute of your demo is an error message. Turn it into a line instead: *"a pin is a
guard, not a decoration — cmux will not let you close your home by accident."*

Closing a workspace takes its panes with it — there is no second cleanup step.

## Act 6 · Land it (30s)

Return to the opening question and answer it in one sentence:

> **"Eight things running, and the rail tells me which one needs me — because cmux is watching
> the agents, not because I remembered to check."**

Then exactly two next steps, no more:

- `/cmux-workflow:lanes` — the state of every agent pane, any time
- `/cmux-workflow:demo` — the same thing with a real codex lane, once they want to run agents

## Verify you left nothing behind

```bash
cmux list-workspaces | diff /tmp/tour-before.txt - && echo "clean"
```

Any `tour-*` workspace still listed is yours to close. If you changed pin, colour or name on
anything that was not created by this tour, restore it now and say so.

## Timing

| Act | Target |
|---|---|
| 0 · the mess | 0:30 |
| 1 · sidebar as queue | 1:30 |
| 2 · workspace per work | 1:00 |
| 3 · panes | 1:00 |
| 4 · **status lane** | 2:30 |
| 5 · closing the loop | 1:00 |
| 6 · land it | 0:30 |

**8 minutes.** If you are running long, cut Act 2 and the todo block — never Act 4. Act 4 is the
only part they will repeat to someone else.

## Deliberately out of scope

Worktrees, SSH/remote workspaces, the browser panel, custom dock and sidebars, agent hibernation,
`cmux vm`. Each is a good second video. In this one they are all the same mistake: answering a
question the audience has not asked yet.
