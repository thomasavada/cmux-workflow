#!/usr/bin/env bash
# SessionStart / compact re-inject: the skill body is gone; this reminder is not.
# Claude Code reads hookSpecificOutput.additionalContext.
# grok SessionStart currently ignores stdout — CLAUDE.md / AGENTS.md is the grok path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL="${PLUGIN_ROOT}/skills/cmux-orchestration/SKILL.md"
LOOP="${PLUGIN_ROOT}/skills/orchestration-loop/SKILL.md"
STATUS="${PLUGIN_ROOT}/skills/cmux-orchestration/lane-status.sh"
ORCA_SKILL="${PLUGIN_ROOT}/skills/orca-orchestration/SKILL.md"
ORCA_STATUS="${PLUGIN_ROOT}/skills/orca-orchestration/orca-lane-status.sh"

# Name both hosts. A reminder that says only "cmux" is ignorable in an Orca
# session — the tool named is not the tool in front of you, so the rule reads as
# someone else's problem. The watcher is the half that gets dropped, so it is
# called out separately rather than left implied by "read the skill".
msg="cmux-workflow: this session started, was cleared, or was compacted — the orchestration skills are NOT in context. Sequential one-by-one implementation is the failure this plugin exists to prevent. Before the next code edit, read ${SKILL} (self-invoke, §0a) and ${LOOP}. Then spawn lanes. If the host is Orca rather than cmux, read ${ORCA_SKILL} instead for the mechanics — the when/how-to-brief rules are shared. ARM THE WATCHER IN THE SAME TURN YOU DISPATCH; a lane nobody is watching turns into the user asking whether it is done. If lanes may already be running: ${STATUS} --all (cmux) or ${ORCA_STATUS} --all (Orca). Durable copy of this rule: CLAUDE.md / AGENTS.md (cmux-workflow-setup)."

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

escaped="$(escape_for_json "$msg")"

# Cursor: additional_context. Claude Code: hookSpecificOutput.additionalContext.
# grok / SDK: additionalContext. Emit only the field this host consumes — Claude Code
# would otherwise inject twice if both additional_context and hookSpecificOutput are set.
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "additional_context": "%s"\n}\n' "$escaped"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ] && [ -z "${GROK_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"
else
  printf '{\n  "additionalContext": "%s"\n}\n' "$escaped"
fi
