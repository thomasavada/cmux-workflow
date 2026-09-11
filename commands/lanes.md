---
description: State of every lane, cmux and Orca — running, done, blocked, dead — then clean up the finished ones
allowed-tools: Bash, Read, Grep, Glob, Skill
---

Run this first, exactly as written:

```bash
ROOT="${CMUX_WORKFLOW_ROOT:-${CLAUDE_PLUGIN_ROOT:-${GROK_PLUGIN_ROOT:-}}}"
if [ ! -f "$ROOT/skills/cmux-orchestration/lane-status.sh" ]; then
  ROOT="$(for b in "$HOME"/.claude/plugins "$HOME"/.codex/plugins "$HOME"/.grok/installed-plugins; do
            find "$b" -maxdepth 7 -path '*skills/cmux-orchestration/lane-status.sh' 2>/dev/null | sort -V | tail -1
          done | head -1)"
  ROOT="${ROOT%/skills/cmux-orchestration/lane-status.sh}"
fi
RAN=0
command -v cmux >/dev/null && {
  RAN=1
  echo "── cmux ──"
  bash "$ROOT/skills/cmux-orchestration/lane-status.sh" $ARGUMENTS
}

# Orca lanes live in a different place and need a different signal. Run both
# rather than guessing the host: a machine can have cmux and Orca installed at
# once, and "no lanes found" from the one you are not using costs a line.
# On Linux a bare `orca` is the GNOME screen reader — require an explicit CLI there.
ORCA_OK=0
[ -n "${ORCA_CLI_COMMAND:-}" ] && ORCA_OK=1
[ "$(uname -s)" != "Linux" ] && command -v orca >/dev/null && ORCA_OK=1
command -v orca-ide >/dev/null && ORCA_OK=1
[ "$ORCA_OK" = "1" ] && [ -f "$ROOT/skills/orca-orchestration/orca-lane-status.sh" ] && {
  RAN=1
  echo "── orca ──"
  bash "$ROOT/skills/orca-orchestration/orca-lane-status.sh" $ARGUMENTS
}

# Silence is the worst answer a diagnostic command can give: it reads as
# "no lanes" when it actually means "I could not look".
[ "$RAN" = "0" ] && echo "neither cmux nor an Orca CLI is on PATH — no lane host to query" >&2
```

(no argument ⇒ the caller's workspace; `--all` ⇒ every workspace; `--json` ⇒ machine-readable)

If the Orca section printed lanes, its states mean something narrower than cmux's: `idle`
is *not working right now*, which includes a lane that stopped to ask you a question. Read
the screen before calling one done. `orca-orchestration` §1 has the detail.

⚠️ **Do not shorten that to `bash ${CLAUDE_PLUGIN_ROOT}/…`.** That variable is set for hook
commands but **not** in the Bash tool's environment, so the path silently collapses to
`/skills/cmux-orchestration/lane-status.sh` and the command dies with "No such file or
directory". Measured on a real install, 2026-08-13.

⚠️ **And do not replace the search with a name glob.** The three hosts install this plugin in
three different shapes — `~/.claude/plugins/cache/<marketplace>/cmux-workflow/<version>/`,
`~/.codex/plugins/cache/<marketplace>/cmux-workflow/<version>/`, and
`~/.grok/installed-plugins/<hash>/`, which **does not contain the plugin name at all**. Two of
the three also carry a version directory, so a hardcoded path breaks on the next upgrade — hence
`sort -V | tail -1`. Searching for the script itself is the only form that works everywhere.

Then **read `cmux-workflow:cmux-orchestration` §5.1** and follow it. This file deliberately does
not restate the rules there — one rule in two places is a failure class this project has already
paid for. Three things §5.1 governs that must not be skipped: `DONE` only means *the turn ended*,
not that the work is right; a `DEAD` lane must never be cleaned up with `git checkout`; and the
`claude` column is not a lane — do not close those.

If any lane is `RUNNING` without a watcher, arm one **in this same turn** — background it with
`Bash(run_in_background: true)` in Claude Code or `run_terminal_command(background: true)` in
grok; in codex run it in the foreground, because nothing there will re-invoke you. The mechanism,
and why nothing else works, is in `cmux-workflow:orchestration-loop`.

Report back one line per lane: state · verified? · committed? · closed? Say plainly what you did
**not** do, and why.
