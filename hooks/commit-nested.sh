#!/usr/bin/env bash
# panma-harness — nested-repo auto-commit helper
#
# Walks the project root for nested git repos (depth 2-3), and for each one
# with changes, stages all and creates a commit. Used as a post-finish.md
# shell rule on polyrepo / nested-clones umbrella projects so that a single
# harness cycle's changes land as one commit per affected nested repo.
#
# Args:
#   $1  optional commit message override. If empty, derived from
#       .harness/state.json's user_request field, else a generic fallback.
#
# Exit 0 on success (including "no changes to commit"). Non-zero only on
# unexpected errors. Prints a per-repo summary to stdout.

set -u

# Resolve the umbrella project root by walking up from CWD looking for a
# `.harness/` marker. CWD is not reliable — Main's hooks may chdir, and the
# user can invoke this from a sub-directory or even from inside a nested
# repo. `.harness/` is always at the umbrella root by definition.
root=""
dir="$(pwd)"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -d "$dir/.harness" ]; then
    root="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$root" ]; then
  echo "commit-nested: could not locate .harness/ in any ancestor of $(pwd)" >&2
  exit 2
fi

cd "$root" || exit 2

# Derive a commit message.
msg="${1:-}"
if [ -z "$msg" ] && [ -f "$root/.harness/state.json" ] && command -v python3 >/dev/null 2>&1; then
  msg="$(python3 -c "
import json, sys
try:
    s = json.load(open('$root/.harness/state.json'))
    req = s.get('user_request', '').strip().splitlines()[0] if s.get('user_request') else ''
    print(req[:72])
except Exception:
    pass
" 2>/dev/null)"
fi
msg="${msg:-harness cycle changes}"
commit_msg="harness: $msg"

# Discover nested repos at depth 2-3 (matches /harness-init detection).
mapfile -t nested < <(cd "$root" && find . -mindepth 2 -maxdepth 3 -name .git -type d 2>/dev/null | sed -e 's|/\.git$||' -e 's|^\./||')

if [ "${#nested[@]}" -eq 0 ]; then
  echo "commit-nested: no nested repos found at depth 2-3"
  exit 0
fi

found=${#nested[@]}
committed=0
clean=0
failed=0

for repo in "${nested[@]}"; do
  repo_dir="$root/$repo"
  [ -d "$repo_dir" ] || continue

  cd "$repo_dir" || { failed=$((failed + 1)); continue; }

  # Skip if nothing to commit (tracked or untracked).
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    clean=$((clean + 1))
    continue
  fi

  if git add -A 2>/dev/null && git commit -m "$commit_msg" >/dev/null 2>&1; then
    committed=$((committed + 1))
    echo "  committed: $repo"
  else
    failed=$((failed + 1))
    echo "  FAILED:    $repo" >&2
  fi
done

cd "$root"

echo
echo "commit-nested: $committed committed, $clean clean, $failed failed (of $found nested repos)"
echo "commit message: \"$commit_msg\""

# Non-zero only on actual failures; clean repos are not failures.
[ "$failed" -eq 0 ]
