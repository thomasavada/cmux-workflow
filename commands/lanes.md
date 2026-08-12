---
description: State of every cmux lane — running, done, blocked, dead — then clean up the finished ones
allowed-tools: Bash, Read, Grep, Glob, Skill
---

Run this first, exactly as written:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -d "$ROOT" ] || ROOT="$(ls -d "$HOME"/.claude/plugins/cache/*/cmux-workflow/*/ 2>/dev/null | sort -V | tail -1)"
[ -d "$ROOT" ] || ROOT="$(ls -d "$HOME"/.claude/plugins/marketplaces/*cmux-workflow 2>/dev/null | tail -1)"
bash "$ROOT/skills/cmux-orchestration/lane-status.sh" $ARGUMENTS
```

(no argument ⇒ the caller's workspace; `--all` ⇒ every workspace; `--json` ⇒ machine-readable)

⚠️ **Do not shorten that to `bash ${CLAUDE_PLUGIN_ROOT}/…`.** That variable is set for hook
commands but **not** in the Bash tool's environment, so the path silently collapses to
`/skills/cmux-orchestration/lane-status.sh` and the command dies with "No such file or
directory". Measured on a real install, 2026-08-13. The installed copy also carries its version
in the path (`…/cmux-workflow/0.1.1/`), so hardcoding it breaks on the next upgrade — hence the
`sort -V | tail -1`.

Then **read `cmux-workflow:cmux-orchestration` §5.1** and follow it. This file deliberately does
not restate the rules there — one rule in two places is a failure class this project has already
paid for. Three things §5.1 governs that must not be skipped: `DONE` only means *the turn ended*,
not that the work is right; a `DEAD` lane must never be cleaned up with `git checkout`; and the
`claude` column is not a lane — do not close those.

If any lane is `RUNNING` without a watcher, arm one **in this same turn** using
`Bash(run_in_background: true)` — the mechanism, and why nothing else works, is in
`cmux-workflow:orchestration-loop`.

Report back one line per lane: state · verified? · committed? · closed? Say plainly what you did
**not** do, and why.
