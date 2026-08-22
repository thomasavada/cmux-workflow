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

msg="cmux-workflow: this session started, was cleared, or was compacted — cmux-orchestration is NOT in context. Sequential one-by-one implementation is the failure this plugin exists to prevent. Before the next code edit, read ${SKILL} (self-invoke, §0a) and ${LOOP}. Then spawn lanes. If lanes may already be running, run ${STATUS} --all first. Durable copy of this rule: CLAUDE.md / AGENTS.md (cmux-workflow-setup)."

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
