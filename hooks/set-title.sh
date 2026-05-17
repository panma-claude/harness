#!/usr/bin/env bash
# panma-harness — session title writer
#
# Invoked by the main Claude (via the Bash tool) at the start of every
# response with a short Korean summary of the user's request:
#
#   bash "$CLAUDE_PLUGIN_ROOT"/hooks/set-title.sh "DB 인덱스 추가"
#
# Writes the title to a per-session sidecar file in $TMPDIR. panma-hud's
# statusline reads this file and displays it as `session_name`, giving the
# HUD an in-turn, lag-free title (no `claude -p` round-trip, no API cost).
#
# Args:
#   $1  the title text (≤15 codepoints recommended; truncated to 15 here)
#
# Env:
#   CLAUDE_CODE_SESSION_ID   set by Claude Code in every Bash tool subshell
#   TMPDIR                   defaults to /tmp
#
# Exit 0 always — failures must never propagate up to disturb the tool call
# in the main conversation. Diagnostics go to stderr only.

set -u

title="${1:-}"
if [ -z "$title" ]; then
  echo "set-title.sh: missing title arg" >&2
  exit 0
fi

# Resolve session id. Claude Code exports CLAUDE_CODE_SESSION_ID for every
# Bash tool subshell.
sid="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$sid" ]; then
  echo "set-title.sh: no session id in env (CLAUDE_CODE_SESSION_ID)" >&2
  exit 0
fi

# Sanitize for filename safety (UUIDs are fine, but be defensive against
# any future change in id format).
sid_safe="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')"
sidecar="${TMPDIR:-/tmp}/panma-harness-title-${sid_safe}.txt"

# Truncate to ≤15 codepoints. When the cut lands mid-word, back off to the
# last space inside the window so we don't display a partial word like
# "마켓 rebase + pus" — better to show "마켓 rebase +" cleanly. Single very
# long words (no space in window) still get a hard cut at 15.
# bash ${#var} counts bytes, so use python for UTF-8 safety.
if command -v python3 >/dev/null 2>&1; then
  title="$(python3 -c '
import sys
t = sys.argv[1]
LIMIT = 15
if len(t) <= LIMIT:
    print(t.rstrip())
else:
    cut = t[:LIMIT]
    # Mid-word cut? backtrack to last space, but only if it actually trims
    # off a partial word (i.e. the char at position LIMIT is non-space).
    if not t[LIMIT].isspace():
        last_space = cut.rfind(" ")
        if last_space > 0:
            cut = cut[:last_space]
    print(cut.rstrip())
' "$title" 2>/dev/null)"
fi
[ -z "$title" ] && exit 0

# Atomic write: tmp file then mv. Avoids HUD reading a half-written line on
# the rare chance it polls mid-write.
tmp="${sidecar}.tmp.$$"
printf '%s\n' "$title" > "$tmp" 2>/dev/null || exit 0
mv -f "$tmp" "$sidecar" 2>/dev/null || rm -f "$tmp"

exit 0
