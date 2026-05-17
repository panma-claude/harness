#!/usr/bin/env bash
# panma-harness updater
#
# Usage:
#   ./update.sh [TARGET_DIR] [--dry-run]
#
# Upgrades an existing harness install in TARGET_DIR. Specifically:
#   - overwrites the four universal agents (designer, generic-executor, verifier, rule-applier)
#   - overwrites all harness-* slash commands
#   - overwrites the orchestration skill
#   - replaces the CLAUDE.md section between panma-harness markers
#   - refreshes .harness/examples/
#
# Preserved:
#   - any other files in .claude/agents/ (user's domain executors)
#   - any other files in .claude/commands/
#   - .harness/state.json and other runtime state
#   - .harness/post-finish.md / repo-registration.yaml / skip-rules.json (user config)
#
# Refuses to run if the harness is not yet installed; use install.sh for fresh setup.

set -euo pipefail

# ----- args & paths -------------------------------------------------
DRY_RUN=0
TARGET_DIR=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /set -euo/d'
      exit 0
      ;;
    -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)  [ -z "$TARGET_DIR" ] && TARGET_DIR="$arg" || { echo "Too many positional args" >&2; exit 2; } ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-$PWD}"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"

[ -d "$TARGET_DIR" ] || { echo "Error: target dir not found: $TARGET_DIR" >&2; exit 1; }
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

MARKER_BEGIN="<!-- panma-harness-include: BEGIN -->"
MARKER_END="<!-- panma-harness-include: END -->"
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

UNIVERSAL_AGENTS=(designer generic-executor verifier rule-applier)
HARNESS_COMMANDS=(harness-start harness-iterate harness-status harness-stop harness-reset)

say() { echo "[update] $*"; }
do_or_show() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "  [dry-run] $*"; else eval "$@"; fi
}

# ----- preflight: must already be installed -------------------------
if [ ! -f "$CLAUDE_MD" ] || ! grep -qF "$MARKER_BEGIN" "$CLAUDE_MD"; then
  echo "Error: harness not installed in $TARGET_DIR (no marker in CLAUDE.md)." >&2
  echo "       Use ./install.sh for a fresh install." >&2
  exit 1
fi

say "Plugin source: $PLUGIN_DIR"
say "Target:        $TARGET_DIR"
[ "$DRY_RUN" -eq 1 ] && say "Mode:          DRY-RUN (no files will change)"

# ----- 1. refresh universal agents ----------------------------------
say "Refreshing universal agents..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/agents'"
for a in "${UNIVERSAL_AGENTS[@]}"; do
  do_or_show "cp '$PLUGIN_DIR/agents/$a.md' '$TARGET_DIR/.claude/agents/$a.md'"
done

# ----- 2. refresh slash commands ------------------------------------
say "Refreshing slash commands..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/commands'"
for c in "${HARNESS_COMMANDS[@]}"; do
  do_or_show "cp '$PLUGIN_DIR/commands/$c.md' '$TARGET_DIR/.claude/commands/$c.md'"
done

# ----- 3. refresh orchestration skill -------------------------------
say "Refreshing orchestration skill..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/skills/harness-orchestration'"
do_or_show "cp '$PLUGIN_DIR/skills/harness-orchestration/SKILL.md' '$TARGET_DIR/.claude/skills/harness-orchestration/SKILL.md'"

# ----- 4. replace CLAUDE.md section between markers -----------------
say "Replacing CLAUDE.md include section between markers..."
if [ "$DRY_RUN" -eq 0 ]; then
  TMP="$(mktemp)"
  # Drop everything between markers (inclusive).
  awk -v B="$MARKER_BEGIN" -v E="$MARKER_END" '
    $0 == B { skip=1; next }
    $0 == E { skip=0; next }
    !skip { print }
  ' "$CLAUDE_MD" > "$TMP"
  mv "$TMP" "$CLAUDE_MD"
  # Trim trailing blank lines before re-appending, for cleanliness.
  awk 'BEGIN{blank=0} NF==0{blank++; next} {for(i=0;i<blank;i++)print ""; blank=0; print}' "$CLAUDE_MD" > "$CLAUDE_MD.tmp"
  mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
  {
    echo ""
    echo "$MARKER_BEGIN"
    cat "$PLUGIN_DIR/CLAUDE-include.md"
    echo "$MARKER_END"
  } >> "$CLAUDE_MD"
else
  echo "  [dry-run] strip and re-insert CLAUDE-include.md between markers in $CLAUDE_MD"
fi

# ----- 5. refresh examples (preserves user files alongside) ---------
say "Refreshing .harness/examples/..."
do_or_show "mkdir -p '$TARGET_DIR/.harness/examples'"
if [ -d "$PLUGIN_DIR/examples" ] && [ -n "$(ls -A "$PLUGIN_DIR/examples" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]; then
  do_or_show "cp -r '$PLUGIN_DIR/examples/'. '$TARGET_DIR/.harness/examples/'"
fi

cat <<EOF

[update] Done.
[update] Refreshed:
[update]   .claude/agents/{$(IFS=,; echo "${UNIVERSAL_AGENTS[*]}")}.md
[update]   .claude/commands/{$(IFS=,; echo "${HARNESS_COMMANDS[*]}")}.md
[update]   .claude/skills/harness-orchestration/SKILL.md
[update]   .harness/examples/
[update]   CLAUDE.md panma-harness section
[update] Preserved:
[update]   .claude/agents/<your-domain>-executor.md (user-defined)
[update]   .harness/state.json + other runtime / user-config files
EOF
