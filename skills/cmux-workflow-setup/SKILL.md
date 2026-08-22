---
name: cmux-workflow-setup
description: Wire cmux-workflow into CLAUDE.md and AGENTS.md so parallel-lane instructions survive conversation compact and still fire when the skill is not auto-invoked. Use when the user says "cmux-workflow-setup", "add this to CLAUDE.md", "add this to AGENTS.md", "make lanes survive compact", "self invoke", or after installing the plugin in a new repo.
---

# Pin cmux-workflow into CLAUDE.md and AGENTS.md

**The failure this prevents:** `cmux-orchestration` is loaded once. A turn that never
auto-invoked it, or a `/compact` (manual or auto) that did, leaves the agent holding the
goal and none of the rules. It then implements the slices itself, one by one, instead of
spawning lanes. Compact does **not** drop `CLAUDE.md` / `AGENTS.md` — those files are
re-injected. This skill writes a short block there that points back at the real skill.

Do not paste the block by hand. The script is idempotent and is the only writer.

## 1 · Run the installer

Same ROOT search as `cmux-orchestration` §5.1, then the script next to this file:

```bash
ROOT="${CMUX_WORKFLOW_ROOT:-${CLAUDE_PLUGIN_ROOT:-${GROK_PLUGIN_ROOT:-}}}"
if [ ! -f "$ROOT/skills/cmux-workflow-setup/install-block.py" ]; then
  ROOT="$(for b in "$HOME"/.claude/plugins "$HOME"/.codex/plugins "$HOME"/.grok/installed-plugins; do
            find "$b" -maxdepth 7 -path '*skills/cmux-workflow-setup/install-block.py' 2>/dev/null | sort -V | tail -1
          done | head -1)"
  ROOT="${ROOT%/skills/cmux-workflow-setup/install-block.py}"
fi

python3 "$ROOT/skills/cmux-workflow-setup/install-block.py"          # ./CLAUDE.md and ./AGENTS.md
python3 "$ROOT/skills/cmux-workflow-setup/install-block.py" --global # also ~/.claude/CLAUDE.md and ~/.grok/AGENTS.md
```

Default is the **project root** (`CLAUDE.md` + `AGENTS.md`). `--global` is the user-level
copy so a repo that has not been set up still recovers after compact. Run both when the
user did not specify.

`--uninstall` removes the marked section. A second install replaces the section in place
— it will not stack duplicates.

## 2 · Confirm

```bash
grep -n "cmux-workflow" CLAUDE.md AGENTS.md
```

Each file must contain `<!-- cmux-workflow -->` and `<!-- /cmux-workflow -->`. Report
the paths the script printed (`created` / `updated` / `unchanged`). Do not then
rephrase the block in the files — the script owns the text.

## 3 · What the block is allowed to say

It names the compact failure, orders a re-read of `cmux-orchestration` §5.0, and forbids
sequential fallback. The five dispatch steps, watcher flags, and host differences stay
in `cmux-orchestration` / `orchestration-loop`. One home per fact.

## Related

- `cmux-orchestration` §0a — the self-invoke rule this block exists to fire
- `orchestration-loop` — arm `lane-watch.sh` once a lane is open
