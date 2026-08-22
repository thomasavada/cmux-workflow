---
description: Wire cmux-workflow into CLAUDE.md and AGENTS.md so lane dispatch survives compact
allowed-tools: Bash, Read, Write, Grep, Glob, Skill
---

Read `cmux-workflow-setup` and follow it. This file does not restate the block or the
ROOT search — the skill owns both.

Default: project `./CLAUDE.md` and `./AGENTS.md`. If the user said "global" or did not
specify, also pass `--global`. If they said "remove" / "uninstall", pass `--uninstall`.

Report the paths the installer printed. Do not edit the marked section by hand afterwards.
