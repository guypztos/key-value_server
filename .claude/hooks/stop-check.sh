#!/usr/bin/env bash
# Claude Code Stop hook: runs the quality gates whenever Claude tries to end a turn.
#
# Exit 0: the gates passed, the turn may end.
# Exit 2: the gates failed. Claude Code blocks the stop and sends stderr back to
#         Claude so it can fix the failure. On a Stop hook only exit code 2 blocks,
#         so every failure is mapped to 2 here, whatever `make` itself returned.
set -u

readonly BLOCK_STOP=2
readonly TAIL_LINES=60

project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
if ! cd "$project_dir"; then
  echo "stop-check: cannot enter project directory: $project_dir" >&2
  exit "$BLOCK_STOP"
fi

# The hook's stdin carries a JSON payload we do not need; keep it away from make.
if output=$(make check 2>&1 </dev/null); then
  exit 0
fi

{
  echo "make check failed, so this turn cannot end yet. Fix the failure and rerun make check."
  echo "Last $TAIL_LINES lines of output:"
  printf '%s\n' "$output" | tail -n "$TAIL_LINES"
} >&2
exit "$BLOCK_STOP"
