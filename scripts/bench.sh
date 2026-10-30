#!/usr/bin/env bash
# The benchmark lives in the skill folder so it ships with the skill.
# This wrapper runs it from a clone of the repo: scripts/bench.sh --help
exec bash "$(dirname "$0")/../skills/cache-tune/scripts/bench.sh" "$@"
