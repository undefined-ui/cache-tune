#!/usr/bin/env bash
# One round: the 5 PRs with the baseline setup, then with the optimized setup.
# Usage: round.sh <round>. Start round 2 at least 65 minutes after round 1 ends, so no PR
# reads the 1-hour cache its own earlier run wrote.
cd "$(dirname "$0")" || exit 1
R=${1:?usage: round.sh <round>}
for n in 1 2 3 4 5; do bash run.sh baseline "$n" "$R" || echo "FAILED baseline pr$n"; done
for n in 1 2 3 4 5; do bash run.sh optimized "$n" "$R" || echo "FAILED optimized pr$n"; done
