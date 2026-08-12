# cmux-workflow

Run several coding agents in parallel as [cmux](https://cmux.com) panes — and actually know the
moment each one finishes.

The failure this exists to prevent: you dispatch three lanes, they all finish in four minutes,
and you find out twenty minutes later because your user told you. Nothing crashed. There was
simply no mechanism that would tell you, and a lane will never remind you.

```
/plugin marketplace add thomasavada/cmux-workflow
/plugin install cmux-workflow
```

## What you get

| | |
|---|---|
| `cmux-workflow:cmux-orchestration` | Pick the tool (lane · teammate · worktree+workspace), write the brief, open the pane, diagnose it, clean it up |
| `cmux-workflow:orchestration-loop` | The watcher mechanism — why the foreground poll you reach for first is blocked, and what condition actually means *done* |
| `cmux-workflow:cmux-screen-layout` | Where the panes go, so four lanes stay readable instead of becoming four unreadable columns |
| `/cmux-workflow:lanes` | One command: the state of every lane right now, and what to verify, commit or close |

Two scripts do the work, and **neither one sends a keystroke into a pane**:

```bash
lane-status.sh --all                    # RUNNING / DONE / BLOCKED / DEAD / EMPTY, per lane
lane-watch.sh 440 442 --timeout-min 60  # run in background; exits when those lanes end their turn
```

## The idea worth stealing, even if you never install this

Most agent-monitoring advice tells you to poll `pgrep` or watch a file appear. Both lie.

- **`pgrep -x codex` counts every codex on the machine.** Its baseline drifted 6 → 8 → 5 in one
  measured session as unrelated projects opened and closed their own lanes.
- **Processes under `surface:N` in `cmux top` do not include codex** — it hangs off a
  workspace-level `tag:codex.<session>` bucket, so three lanes visibly mid-turn showed nothing
  but `zsh`. A liveness check built on that calls working lanes dead.
- **A file appearing tells you the worker *started*.** It fires, you look, and then nothing is
  watching again.

cmux already knows the answer. It installs turn hooks into codex, grok and claude, and keeps a
session store at `~/.cmuxterm/<agent>-hook-sessions.json` where each entry carries `surfaceId`,
`pid`, `transcriptPath`, `updatedAt`, and **`agentLifecycle`: `running` · `idle` · `needsInput`**.

`idle` means *the turn ended*, written by the agent's own Stop hook. It is a recorded fact, it
costs one file read, and it is per-surface. That is the whole trick.

Two rules keep it honest, and both come from getting them wrong first:

- **Compare `updatedAt` against a baseline stamped when you started watching.** The store already
  holds `idle` from previous turns; a bare presence test fires instantly on stale state.
- **`running` + a dead pid is a crash, not work.** Nothing ever writes `idle` for a killed
  process, so that entry reads RUNNING forever.

## Requirements

- **[cmux](https://cmux.com)** with its CLI on `PATH`
- **Agent hooks installed** — this is what populates the session store:
  ```bash
  cmux hooks setup          # or: cmux hooks setup codex
  ```
  Verify: `ls ~/.cmuxterm/*-hook-sessions.json` should list a file per agent you use.
- **`python3`** (bundled with macOS) — the scripts parse the store with it
- At least one agent CLI: `codex`, `grok`, or another one cmux integrates

**cmux's own skills are not bundled here.** `cmux`, `cmux-workspace`, `cmux-diagnostics` and the
rest are [manaflow-ai's](https://cmux.com/docs/skills) and ship with cmux — install them with
`npx skills add manaflow-ai/cmux -g -y`. This plugin calls the `cmux` **CLI** directly and does
not depend on them, and vendoring a copy would only fork a project that updates on its own
schedule.

## Where this came from

Every rule in these skills is anchored to a specific failure in a real multi-lane session, with
the date and the cost. A few of them:

- A lane died at 10:27 and was reported as *"running"* for **three hours**, because panes were
  being counted instead of surfaces being reconciled. Its work sat uncommitted the whole time.
- `cmux send` types **keystrokes**. Sent into a pane where codex is still running, the command
  lands in codex's input box and never executes — no error, no signal.
- Three watchers fired early and reported success, all because their condition named the
  *neighbourhood* (a directory, a URL being present) instead of the deliverable.
- Five lanes finished and the user reported *"none of them committed anything"* — everything was
  committed locally and nothing had been pushed.

The skills are written to be read by an agent, so they are blunt about which mistakes cost what.
If you disagree with a rule, the incident behind it is stated inline; argue with that.

## Licence

MIT. See [LICENSE](LICENSE).
