#!/usr/bin/env bash
# One review run. Usage: run.sh <baseline|optimized> <pr-index 1..5> <round>
# FASTAPI_DIR must point at a clone of https://github.com/fastapi/fastapi used only for this
# benchmark: every run force-checks out the PR's parent commit there and runs git clean -fdx.
set -u
export MSYS_NO_PATHCONV=1
VER="$1"; N="$2"; ROUND="$3"
ROOT=$(cd "$(dirname "$0")" && pwd)
REPO=${FASTAPI_DIR:?set FASTAPI_DIR to a dedicated fastapi clone}
DIFF=$(ls "$ROOT"/diffs/pr"$N"-*.diff)
PR=$(basename "$DIFF" .diff | cut -d- -f2)
PARENT=$(grep "^$PR " "$ROOT/parents.txt" | cut -d" " -f2)
BRANCH="review/pr-$PR"
DATE=$(date +%F)
OUT=$ROOT/runs/$VER-r$ROUND/pr$N-$PR; mkdir -p "$OUT"

# clean state: fresh checkout of the parent commit on a per-PR branch, no untracked files
cd "$REPO" || exit 1
git checkout -q -f -B "$BRANCH" "$PARENT" && git clean -q -fdx || { echo "checkout failed for $PR" >&2; exit 1; }
[ "$(git rev-parse HEAD)" = "$PARENT" ] || { echo "HEAD mismatch for $PR" >&2; exit 1; }

source "$ROOT/$VER/setup.sh"   # defines PROMPT, CLAUDE_ARGS, STDIN_FILE and writes per-version files into $REPO

start=$(date +%s)
claude -p "$PROMPT" --model sonnet --output-format json --permission-mode bypassPermissions \
  ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"} < "$STDIN_FILE" > "$OUT/result.json" 2> "$OUT/stderr.txt"
end=$(date +%s)
echo "$start $end" > "$OUT/wallclock.txt"
cp "$REPO/CLAUDE.md" "$OUT/CLAUDE.md" 2>/dev/null

PY=python3; "$PY" -c '' 2>/dev/null || PY=python
echo "$VER r$ROUND pr$N ($PR) done: $("$PY" -c 'import json,sys; d=json.load(sys.stdin); print(round(d["total_cost_usd"],4), d["duration_ms"], d["num_turns"])' < "$OUT/result.json")"
