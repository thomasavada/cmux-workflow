# cmux-workflow

Run several coding agents in parallel as [cmux](https://cmux.com) panes — and actually know the
moment each one finishes.

The failure this exists to prevent: you dispatch three lanes, they all finish in four minutes,
and you find out twenty minutes later because your user told you. Nothing crashed. There was
simply no mechanism that would tell you, and a lane will never remind you.

## Install

Works in **Claude Code**, **codex** and **grok** — one repository, one `.claude-plugin/`
manifest, which all three read.

```
# Claude Code
/plugin marketplace add thomasavada/cmux-workflow
/plugin install cmux-workflow
```

```bash
# codex
codex plugin marketplace add thomasavada/cmux-workflow
codex plugin add cmux-workflow@thomasavada-cmux-workflow

# grok
grok plugin install thomasavada/cmux-workflow --trust
```

Verified on real installs, 2026-08-16: `codex plugin marketplace add` reads
`.claude-plugin/marketplace.json` directly, and `grok plugin validate` reports the manifest valid
(*"grok reads the index from `.grok-plugin/marketplace.json`. It also accepts … the
`.claude-plugin/` equivalents."*). So there is deliberately **no** duplicate `.codex-plugin/` or
`.grok-plugin/` manifest here — three copies of a version number is three chances to ship a
mismatch.

The **skills** load in all three. Whether the two **slash commands** appear is host-dependent —
Claude Code and grok both list plugin commands (grok reports `1 skill dir(s), 1 command dir(s)`
for this plugin); codex was only verified to install and expose the skills. If `/cmux-workflow:lanes`
is not there, it was never more than a wrapper: run
`"$ROOT"/skills/cmux-orchestration/lane-status.sh --all` and you have the same thing.

**One thing genuinely differs between hosts, and the skills say so where it matters:** Claude Code
and grok notify you when a background command exits; **codex does not**, so there the watcher runs
in the foreground. Same script, same signal, different call. See `orchestration-loop`
§ *Three hosts, one mechanism, different tool names*.

## What you get

| | |
|---|---|
| `cmux-workflow:cmux-orchestration` | Pick the tool (lane · teammate · worktree+workspace), write the brief, open the pane, diagnose it, clean it up. Self-invokes after compact — sequential one-by-one work is the failure, not a fallback |
| `cmux-workflow:orchestration-loop` | The watcher mechanism — why the foreground poll you reach for first is blocked, and what condition actually means *done* |
| `cmux-workflow:cmux-screen-layout` | Where the panes go, so four lanes stay readable instead of becoming four unreadable columns |
| `cmux-workflow:cmux-workflow-setup` | Pin a compact-survival block into `CLAUDE.md` and `AGENTS.md` so the skill still fires when it was not auto-invoked, and after `/compact` |
| `/cmux-workflow:lanes` | One command: the state of every lane right now, and what to verify, commit or close |
| `/cmux-workflow:setup` | Run the setup skill — writes (or refreshes) the `CLAUDE.md` / `AGENTS.md` block |
| `/cmux-workflow:demo` | A live guided walkthrough — sidebar, groups, status lanes, four agents at once, then a clean teardown |
| `cmux-workflow:orca-orchestration` | The same discipline, hosted in **Orca** instead of cmux. Owns only what differs: terminal creation, the probe, the flag traps, and a completion signal that works |
| `/cmux-workflow:orca-demo` | The Orca walkthrough — two lanes, a watcher armed in the same turn, and the four traps that each cost a real session. Built around the one thing Orca cannot tell you |

Two scripts do the work, and **neither one sends a keystroke into a pane**:

```bash
lane-status.sh --all                    # RUNNING / DONE / BLOCKED / DEAD / EMPTY, per lane
lane-watch.sh 440 442 --timeout-min 60  # run in background; exits when those lanes end their turn
```

Orca gets its own pair, because the signal cmux relies on does not exist there:

```bash
orca-lane-status.sh --all                          # busy / idle / unknown, per lane
orca-lane-watch.sh --handles term_aaa,term_bbb     # exits on the busy→idle transition
orca-lane-watch.sh --auto                          # every codex lane in this worktree
```

**Why Orca needs a different watcher.** cmux publishes `agentLifecycle: idle` from its
own turn-hook store — a recorded fact. Orca has no equivalent: `orca terminal wait --for
tui-idle` reports idle *mid-turn*. The obvious replacement, codex's `─ Worked for 27m 57s ─`
footer, is worse than it looks — it is printed only for long turns, so a watcher built on it
passes every test against slow lanes and then hangs forever on a fast one. The Orca watcher
reads the input box instead (`esc to interrupt` = busy; the prompt with no busy marker =
idle) and refuses to call a lane done until it has seen it busy, so a terminal parked at its
prompt cannot settle it instantly.

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
- At least one agent CLI to run *in* the lanes: `codex`, `grok`, `claude`, or another one cmux
  integrates. This is independent of which CLI you orchestrate *from* — a Claude Code session can
  drive codex lanes, a codex session can drive grok lanes, and so on.
- Optional: export `CMUX_WORKFLOW_ROOT=<install path>` to skip the plugin-root search the skills
  do (each host installs to a different path shape, and grok's does not contain the plugin name)

## Compact drops the skill — pin it into CLAUDE.md / AGENTS.md

A skill body is loaded once. `/compact`, auto-compact, and a turn that never auto-invoked
`cmux-orchestration` all leave the agent holding the goal and none of the rules. The default
after that is to implement the slices **in the orchestrating chat, one file at a time**.

`CLAUDE.md` and `AGENTS.md` are re-injected after compact. The skill is not. Run this once
per repo (and once with `--global` if you want it in every project):

```
/cmux-workflow:setup
```

```bash
python3 "$ROOT/skills/cmux-workflow-setup/install-block.py"          # ./CLAUDE.md + ./AGENTS.md
python3 "$ROOT/skills/cmux-workflow-setup/install-block.py" --global # ~/.claude/CLAUDE.md + ~/.grok/AGENTS.md
```

The installer is idempotent. It writes a marked section that says: re-read
`cmux-orchestration` this turn, spawn lanes, do not continue sequentially. Claude Code also
re-injects a short reminder on session start / clear / compact via `hooks/reinvoke.sh`.
grok's SessionStart hook cannot inject context, which is why the markdown files are the
cross-host path.

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
- After compact the skill body is gone, and the orchestrator continues the remaining slices
  itself one-by-one instead of re-spawning lanes *(2026-08-22)*.

The skills are written to be read by an agent, so they are blunt about which mistakes cost what.
If you disagree with a rule, the incident behind it is stated inline; argue with that.

## Licence

MIT. See [LICENSE](LICENSE).
