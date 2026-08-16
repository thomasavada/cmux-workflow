---
description: State of every cmux lane — running, done, blocked, dead — then clean up the finished ones
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
bash "$ROOT/skills/cmux-orchestration/lane-status.sh" $ARGUMENTS
```

(no argument ⇒ the caller's workspace; `--all` ⇒ every workspace; `--json` ⇒ machine-readable)

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
