#!/usr/bin/env bash
# panma-harness — UserPromptSubmit hook
#
# Emits the harness activation trigger directive to stdout on every user
# prompt. Claude reads the output as additional context and decides whether
# to enter harness mode based on the trigger conditions stated in
# CLAUDE-include.md.
#
# $CLAUDE_PLUGIN_ROOT is set by Claude Code to the plugin's installed path.

set -e

INCLUDE_FILE="${CLAUDE_PLUGIN_ROOT}/CLAUDE-include.md"

if [ -f "$INCLUDE_FILE" ]; then
  cat "$INCLUDE_FILE"
fi
