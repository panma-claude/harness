#!/usr/bin/env bash
# panma-harness installer
#
# Usage:
#   ./install.sh [TARGET_DIR] [--dry-run]
#
# Installs the harness into the target project:
#   - copies universal agents / commands / orchestration skill into TARGET_DIR/.claude/
#   - appends CLAUDE-include.md between markers in TARGET_DIR/CLAUDE.md (creates if missing)
#   - creates TARGET_DIR/.harness/ and copies examples/ into TARGET_DIR/.harness/examples/
#   - suggests .gitignore entries for runtime state files
#
# Idempotency: refuses to run if the harness is already installed (marker present).
# Conflict policy: refuses to overwrite pre-existing files in .claude/agents/ that
#                  share a name with one of our universal agents. Use update.sh for
#                  upgrading an existing install.

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
    -*)
      echo "Unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      [ -z "$TARGET_DIR" ] && TARGET_DIR="$arg" || { echo "Too many positional args" >&2; exit 2; }
      ;;
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

# ----- helpers ------------------------------------------------------
say()  { echo "[install] $*"; }
do_or_show() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] $*"
  else
    eval "$@"
  fi
}

# ----- preflight: already installed? --------------------------------
if [ -f "$CLAUDE_MD" ] && grep -qF "$MARKER_BEGIN" "$CLAUDE_MD"; then
  echo "Error: harness already installed (marker found in $CLAUDE_MD)." >&2
  echo "       Use ./update.sh to upgrade, or ./uninstall.sh to remove first." >&2
  exit 1
fi

# ----- preflight: file conflicts ------------------------------------
CONFLICTS=()
for a in "${UNIVERSAL_AGENTS[@]}"; do
  [ -f "$TARGET_DIR/.claude/agents/$a.md" ] && CONFLICTS+=(".claude/agents/$a.md")
done
for c in "${HARNESS_COMMANDS[@]}"; do
  [ -f "$TARGET_DIR/.claude/commands/$c.md" ] && CONFLICTS+=(".claude/commands/$c.md")
done
[ -d "$TARGET_DIR/.claude/skills/harness-orchestration" ] && CONFLICTS+=(".claude/skills/harness-orchestration/")

if [ ${#CONFLICTS[@]} -gt 0 ]; then
  echo "Error: pre-existing files would be overwritten:" >&2
  for f in "${CONFLICTS[@]}"; do echo "  - $f" >&2; done
  echo "       Remove them first, or use update.sh if these are from a prior harness install." >&2
  exit 1
fi

say "Plugin source: $PLUGIN_DIR"
say "Target:        $TARGET_DIR"
[ "$DRY_RUN" -eq 1 ] && say "Mode:          DRY-RUN (no files will change)"

# ----- 1. copy plugin files into .claude/ ---------------------------
say "Copying universal agents..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/agents'"
for a in "${UNIVERSAL_AGENTS[@]}"; do
  do_or_show "cp '$PLUGIN_DIR/agents/$a.md' '$TARGET_DIR/.claude/agents/$a.md'"
done

say "Copying slash commands..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/commands'"
for c in "${HARNESS_COMMANDS[@]}"; do
  do_or_show "cp '$PLUGIN_DIR/commands/$c.md' '$TARGET_DIR/.claude/commands/$c.md'"
done

say "Copying orchestration skill..."
do_or_show "mkdir -p '$TARGET_DIR/.claude/skills/harness-orchestration'"
do_or_show "cp '$PLUGIN_DIR/skills/harness-orchestration/SKILL.md' '$TARGET_DIR/.claude/skills/harness-orchestration/SKILL.md'"

# ----- 2. append include to CLAUDE.md -------------------------------
say "Appending include section to CLAUDE.md..."
if [ "$DRY_RUN" -eq 0 ]; then
  [ -f "$CLAUDE_MD" ] || touch "$CLAUDE_MD"
  {
    echo ""
    echo "$MARKER_BEGIN"
    cat "$PLUGIN_DIR/CLAUDE-include.md"
    echo "$MARKER_END"
  } >> "$CLAUDE_MD"
else
  echo "  [dry-run] append CLAUDE-include.md to $CLAUDE_MD between markers"
fi

# ----- 3. .harness/ workspace + examples ----------------------------
say "Creating .harness/ workspace..."
do_or_show "mkdir -p '$TARGET_DIR/.harness/examples'"
if [ -d "$PLUGIN_DIR/examples" ] && [ -n "$(ls -A "$PLUGIN_DIR/examples" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]; then
  do_or_show "cp -r '$PLUGIN_DIR/examples/'. '$TARGET_DIR/.harness/examples/'"
fi

# ----- 4. .gitignore suggestion -------------------------------------
GITIGNORE="$TARGET_DIR/.gitignore"
NEEDS_IGNORE=(
  ".harness/state.json"
  ".harness/STOP"
  ".harness/cycle-*.applied"
)
MISSING_IGNORES=()
if [ -f "$GITIGNORE" ]; then
  for entry in "${NEEDS_IGNORE[@]}"; do
    grep -qxF "$entry" "$GITIGNORE" || MISSING_IGNORES+=("$entry")
  done
else
  MISSING_IGNORES=("${NEEDS_IGNORE[@]}")
fi

if [ ${#MISSING_IGNORES[@]} -gt 0 ]; then
  say "Suggested .gitignore additions (not applied automatically):"
  for entry in "${MISSING_IGNORES[@]}"; do echo "  $entry"; done
fi

# ----- 5. summary ---------------------------------------------------
cat <<EOF

[install] Done.
[install] Installed:
[install]   .claude/agents/{$(IFS=,; echo "${UNIVERSAL_AGENTS[*]}")}.md
[install]   .claude/commands/{$(IFS=,; echo "${HARNESS_COMMANDS[*]}")}.md
[install]   .claude/skills/harness-orchestration/SKILL.md
[install]   .harness/                         (runtime workspace)
[install]   .harness/examples/                (copy-paste templates)
[install]   CLAUDE.md  +include section (between panma-harness markers)

Next steps (optional, for full power):

  1) Define domain executors for your project:
       ls .harness/examples/
       cp .harness/examples/<your-domain>-executor.md.example \\
          .claude/agents/<your-domain>-executor.md
     Then edit it: replace placeholders with your stack's build/test command,
     domain name, and any project-specific constraints.

  2) Enable auto repo registration:
       cp .harness/examples/repo-registration.yaml.example .harness/repo-registration.yaml

  3) Add project-specific finish rules:
       cp .harness/examples/post-finish.md.example .harness/post-finish.md

You can start using the harness right away even without the optional steps —
generic-executor will absorb any work that has no specialized executor.
EOF
