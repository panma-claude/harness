#!/usr/bin/env bash
# panma-harness — UserPromptSubmit hook
#
# Emits two things to stdout (additionalContext that Claude reads):
#   1. The static CLAUDE-include.md content (auto-activation trigger rules).
#   2. A dynamically-built session-title directive that includes the absolute
#      path to set-title.sh, because $CLAUDE_PLUGIN_ROOT is NOT available in
#      the main model's Bash tool execution environment — only here.
#
# $CLAUDE_PLUGIN_ROOT is set by Claude Code to the plugin's installed path.

set -e

INCLUDE_FILE="${CLAUDE_PLUGIN_ROOT}/CLAUDE-include.md"
SET_TITLE="${CLAUDE_PLUGIN_ROOT}/hooks/set-title.sh"

if [ -f "$INCLUDE_FILE" ]; then
  cat "$INCLUDE_FILE"
fi

# Append the session-title directive only if the script actually exists in
# this install — keeps the hook usable on older deployments that lack it.
if [ -x "$SET_TITLE" ]; then
  cat <<EOF

---

# panma-harness — Session Title

Before producing your response to the user's request, run **once** as your first action:

\`\`\`
Bash(command='bash "${SET_TITLE}" "<≤15-char Korean summary of the user request>"', description='Set HUD session title')
\`\`\`

Replace \`<…>\` with a tight Korean phrase (≤15 codepoints) that captures the user's intent — e.g. \`"DB 인덱스 추가"\`, \`"로그인 버그 수정"\`, \`"HUD 폰트 변경"\`. This updates the panma-hud statusline title in real time.

Rules:
- Run this **exactly once per turn**, before any other tool use or substantive response.
- Skip for trivial messages with no actionable intent (single-word replies, "ok", "thanks", pure conversation).
- Skip for slash-command-only inputs (e.g. \`/clear\`).
- The script is silent on success; do not surface its output to the user.
EOF
fi
