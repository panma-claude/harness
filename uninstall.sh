#!/usr/bin/env bash
# panma-harness uninstaller
#
# Usage:
#   ./uninstall.sh [TARGET_DIR] [--purge] [--dry-run]
#
# Removes only what this plugin installed:
#   - the four universal agents (designer, generic-executor, verifier, rule-applier)
#   - all harness-* slash commands
#   - the orchestration skill directory
#   - the CLAUDE.md section between panma-harness markers
#
# Preserved by default:
#   - .claude/agents/<your-domain>-executor.md  (user-defined domain executors)
#   - .harness/                                  (runtime state + user config)
#   - .harness/examples/                         (templates copied at install)
#
# With --purge: also removes .harness/ entirely. Destructive — use with care.

set -euo pipefail

# ----- args & paths -------------------------------------------------
DRY_RUN=0
PURGE=0
TARGET_DIR=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --purge)   PURGE=1 ;;
    --help|-h)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /set -euo/d'
      exit 0
      ;;
    -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)  [ -z "$TARGET_DIR" ] && TARGET_DIR="$arg" || { echo "Too many positional args" >&2; exit 2; } ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-$PWD}"
[ -d "$TARGET_DIR" ] || { echo "Error: target dir not found: $TARGET_DIR" >&2; exit 1; }
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

MARKER_BEGIN="<!-- panma-harness-include: BEGIN -->"
MARKER_END="<!-- panma-harness-include: END -->"
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

UNIVERSAL_AGENTS=(designer generic-executor verifier rule-applier)
HARNESS_COMMANDS=(harness-start harness-iterate harness-status harness-stop harness-reset)

say() { echo "[uninstall] $*"; }
do_or_show() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "  [dry-run] $*"; else eval "$@"; fi
}

# ----- preflight ----------------------------------------------------
if [ ! -f "$CLAUDE_MD" ] || ! grep -qF "$MARKER_BEGIN" "$CLAUDE_MD"; then
  say "Warning: no panma-harness marker found in $CLAUDE_MD."
  say "         Will still remove any installed agents/commands/skill files if present."
fi

say "Target:        $TARGET_DIR"
[ "$PURGE" -eq 1 ]   && say "Mode:          PURGE (.harness/ will be removed)"
[ "$DRY_RUN" -eq 1 ] && say "Mode:          DRY-RUN (no files will change)"

# ----- 1. remove universal agents -----------------------------------
say "Removing universal agents..."
for a in "${UNIVERSAL_AGENTS[@]}"; do
  f="$TARGET_DIR/.claude/agents/$a.md"
  [ -f "$f" ] && do_or_show "rm '$f'"
done

# ----- 2. remove slash commands -------------------------------------
say "Removing slash commands..."
for c in "${HARNESS_COMMANDS[@]}"; do
  f="$TARGET_DIR/.claude/commands/$c.md"
  [ -f "$f" ] && do_or_show "rm '$f'"
done

# ----- 3. remove orchestration skill --------------------------------
say "Removing orchestration skill..."
SKILL_DIR="$TARGET_DIR/.claude/skills/harness-orchestration"
[ -d "$SKILL_DIR" ] && do_or_show "rm -rf '$SKILL_DIR'"

# ----- 4. strip CLAUDE.md section between markers -------------------
if [ -f "$CLAUDE_MD" ] && grep -qF "$MARKER_BEGIN" "$CLAUDE_MD"; then
  say "Removing CLAUDE.md panma-harness section..."
  if [ "$DRY_RUN" -eq 0 ]; then
    TMP="$(mktemp)"
    awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" '
      $0 == B { skip=1; next }
      $0 == E { skip=0; next }
      !skip { print }
    ' "$CLAUDE_MD" > "$TMP"
    # Trim trailing blank lines for cleanliness.
    awk 'BEGIN{blank=0} NF==0{blank++; next} {for(i=0;i<blank;i++)print ""; blank=0; print}' "$TMP" > "$CLAUDE_MD"
    rm -f "$TMP"
  else
    echo "  [dry-run] strip CLAUDE-include section between markers in $CLAUDE_MD"
  fi
fi

# ----- 5. purge .harness/ if requested ------------------------------
if [ "$PURGE" -eq 1 ] && [ -d "$TARGET_DIR/.harness" ]; then
  say "Purging .harness/..."
  do_or_show "rm -rf '$TARGET_DIR/.harness'"
fi

# ----- 6. cleanup empty dirs ----------------------------------------
for d in "$TARGET_DIR/.claude/agents" "$TARGET_DIR/.claude/commands" "$TARGET_DIR/.claude/skills" "$TARGET_DIR/.claude"; do
  if [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
    do_or_show "rmdir '$d'"
  fi
done

cat <<EOF

[uninstall] Done.
[uninstall] Removed:
[uninstall]   .claude/agents/{$(IFS=,; echo "${UNIVERSAL_AGENTS[*]}")}.md
[uninstall]   .claude/commands/{$(IFS=,; echo "${HARNESS_COMMANDS[*]}")}.md
[uninstall]   .claude/skills/harness-orchestration/
[uninstall]   CLAUDE.md panma-harness section
$([ "$PURGE" -eq 1 ] && echo "[uninstall]   .harness/ (purged)")
[uninstall] Preserved:
[uninstall]   .claude/agents/<your-domain>-executor.md (user-defined)
$([ "$PURGE" -eq 0 ] && echo "[uninstall]   .harness/state.json + user config (post-finish.md / repo-registration.yaml / skip-rules.json)")
EOF
