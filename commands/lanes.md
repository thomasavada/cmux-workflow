---
description: State of every cmux lane — running, done, blocked, dead — then clean up the finished ones
allowed-tools: Bash, Read, Grep, Glob, Skill
---

Run this first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cmux-orchestration/lane-status.sh $ARGUMENTS
```

(no argument ⇒ the caller's workspace; `--all` ⇒ every workspace; `--json` ⇒ machine-readable)

Then **read `cmux-orchestration` §5.1** and follow it. This file deliberately does not restate the rules there — one rule in two places is a failure class this project has already paid for. Three things §5.1 governs that must not be skipped: `DONE` only means *the turn ended*, not that the work is right; a `DEAD` lane must never be cleaned up with `git checkout`; and the `claude` column is not a lane — do not close those.

If any lane is `RUNNING` without a watcher, arm one **in this same turn** using `Bash(run_in_background: true)` — the mechanism, and why nothing else works, is in `orchestration-loop`.

Report back one line per lane: state · verified? · committed? · closed? Say plainly what you did **not** do, and why.
